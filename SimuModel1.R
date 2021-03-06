rm(list = ls())
## Data Simulation Generation
propScoreM1 = function(A, W){ # Or a function of Z
  # propensity score model to generate T
  ###############################
  # A --- a vec of length 6
  # W --- a vec of length 3
  ###############################
  
  # Model1 only linear part
  -W[1] + 0.5*W[2] - 0.1*W[3] + 2*A[1] + 0.5*A[2] + 0.5*A[3] + A[4]
}


funcCov = function(A,delta,h){
  # generate a smooth curve on [0,1] by coefficients A and a basis, add gaussian noise with SNR=1/delta
  ###############################
  # A --- a vec of length 6
  # delta --- a small positive real number
  # h --- bandwidth
  ###############################
  t = seq(from = 0, to = 1, by = h)
  X = sqrt(2) * (A[1] * sin(2*pi*t) + A[2] * cos(2*pi*t) 
                 + A[3] * sin(4*pi*t) + A[4] * cos(4*pi*t) 
                 + A[5] * sin(8*pi*t) + A[6] * cos(8*pi*t))
  ## X = X + rnorm(length(t), mean = 0, sd = delta * sd(X))
}


treatEff = function(T, Z){ # Or a function of Z
  # treatment effect model to generate Y
  ###############################
  # T --- binary variable 0 or 1
  # A --- a vec of length 6
  # W --- a vec of length 3
  ###############################
  
  200 + 10*T + (1.5*T - 0.5) * (27.4*Z[1] + 13.7*Z[2] + 13.7*Z[3] + 13.7*Z[4]) + rnorm(1)
  
}

set.seed(1000)
data_simu_M1 = t(sapply(1:100000, function(k){
  Z  = rnorm(6)
  A  = 2*Z/(1:6)
  W1 = Z[1] + 2*Z[2]         # Or other function of Z s.t. E W1 = 0 
  W2 = Z[2]^2 -Z[3]^2        # Or other function of Z s.t. E W2 = 0 
  W3 = exp(Z[3]) - exp(0.5)  # Or other function of Z s.t. E W3 = 0 
  W  = c(W1,W2,W3)
  T  = rbinom(n = 1, size = 1, prob = boot::inv.logit(propScoreM1(A,W)))
  Y  = treatEff(T, Z)
  X  = funcCov(A, delta = 0.1, h = 0.02)
  c(Y,T,W,X)
}))

######################  
### FPCA function  ###
######################

FPCA = function(sampMat, percent = 0.95) {
  # Return
  #       1. eigenvalues
  #       2. eigenfunctions
  #       3. A matrix of projected coefficients, same nrow as sampMat
  ###############################
  data.basis = create.bspline.basis(c(0,1), nbasis = 10)
  sampMat.fd = smooth.basis(seq(0, 1, length=ncol(sampMat)),t(sampMat), fdParobj = data.basis)
  sampMat.fpca = pca.fd(sampMat.fd$fd, nharm = 6)
  Num_fpca = sum(as.integer(cumsum(sampMat.fpca$varprop) < percent))+1
  sampMat.fpca$scores[, 1:Num_fpca]
}


library(doParallel)

## True Model 1

Model1 = foreach(B = 1:1000, .combine = 'rbind') %dopar% {
  n = 200
  set.seed(1000+B)
  data_raw = data_simu_M1[sample.int(nrow(data_simu_M1), n, replace = F), ]  # sample 200 rows from data_simu

  ######################
  ### GFPLM Fitting ####
  ######################
  
  data = cbind(data_raw[,1:5], FPCA(data_raw[,6:ncol(data_raw)])) # combine Y,T,W,PC scores of X
  Ncol = ncol(data)
  glmFit = glm(data[,2] ~ data[,3:Ncol], family = 'binomial')
  p_hat_glm = predict(glmFit, type = "response") # Be careful when some p_hat = 0
  
  tau_HT_glm  = mean(data[,1]*data[,2]/p_hat_glm - data[,1]*(1-data[,2])/(1-p_hat_glm))
  tau_Hajek_glm = (sum(data[,1]*data[,2]/p_hat_glm)/sum(data[,2]/p_hat_glm) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_glm))/sum((1-data[,2])/(1-p_hat_glm)))
  
  ######################
  #### FGAM Fitting ####
  ######################
  
  S = matrix(rep(seq(0,1,length = 51), n), nrow = n)
  gamFit = gam(data_raw[, 2] ~ data_raw[, 3:5] + 
                 te(data_raw[, 6:ncol(data_raw)], S, bs = 'cr',
                    k = c(7, 7), m = list(c(2, 1), c(2, 1))), family = 'binomial')
  p_hat_gam = predict(gamFit, type = "response") # Be careful when some p_hat = 0
  
  tau_HT_gam    = mean(data[,1]*data[,2]/p_hat_gam - data[,1]*(1-data[,2])/(1-p_hat_gam))
  tau_Hajek_gam = sum(data[,1]*data[,2]/p_hat_gam)/sum(data[,2]/p_hat_gam) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_gam))/sum((1-data[,2])/(1-p_hat_gam))
  
  
  
  ######################
  ######  CBPS  ########
  ######################
  
  CBPSFit1 = CBPS(data[, 2] ~ data[, 3:Ncol], ATT = 0)
  p_hat_CBPS1 = CBPSFit1$fitted.values
  tau_HT_CBPS1    = mean(data[,1]*data[,2]/p_hat_CBPS1 - data[,1]*(1-data[,2])/(1-p_hat_CBPS1))
  tau_Hajek_CBPS1 = sum(data[,1]*data[,2]/p_hat_CBPS1)/sum(data[,2]/p_hat_CBPS1) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_CBPS1))/sum((1-data[,2])/(1-p_hat_CBPS1))
   
  
  
  X_CBPS2 = cbind(data[, 3:Ncol],data[, 3:Ncol]^2)
  CBPSFit2 = CBPS(data[, 2] ~ X_CBPS2, ATT = 0)
  p_hat_CBPS2 = CBPSFit2$fitted.values
  tau_HT_CBPS2   = mean(data[,1]*data[,2]/p_hat_CBPS2 - data[,1]*(1-data[,2])/(1-p_hat_CBPS2))
  tau_Hajek_CBPS2 = sum(data[,1]*data[,2]/p_hat_CBPS2)/sum(data[,2]/p_hat_CBPS2) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_CBPS2))/sum((1-data[,2])/(1-p_hat_CBPS2))
 
  c(tau_HT_glm,tau_Hajek_glm, tau_HT_gam, tau_Hajek_gam, tau_HT_CBPS1, tau_Hajek_CBPS1,
    tau_Hajek_CBPS2, tau_Hajek_CBPS2) #tau_HT_KBCBPS, tau_Hajek_KBCBPS
}


Model1_KBCBPS = foreach(B = 1:1000, .combine = 'rbind') %dopar% {
  n = 200
  set.seed(1000+B)
  data_raw = data_simu_M1[sample.int(nrow(data_simu_M1), n, replace = F), ]  # sample 200 rows from data_simu
  data = cbind(data_raw[,1:5], FPCA(data_raw[,6:ncol(data_raw)])) # combine Y,T,W,PC scores of X
  Ncol = ncol(data)
  data_std <- transform.sob(data[, 3:Ncol])$Xstd # standardize X to [0,1]^p
  K <- getGram(data_std) # get Gram matrix using Sobolev kernel
  
  # design a grid for the tuning parameter
  nlam <- 50
  lams <- exp(seq(log(1e-8), log(1), len=nlam))
  
  # compute weights for T=1
  RKHS_fit1 <- ATE.ncb.SN(data[,2], K, lam1s=lams)
  if (sum(RKHS_fit1$warns)) cat("lambda bound warning!\n")
  
  
  #### T=0 ####
  
  # compute weights for T=0
  RKHS_fit0 <- ATE.ncb.SN(1-data[,2], K, lam1s=lams)
  if (sum(RKHS_fit0$warns)) cat("lambda bound warning!\n")
  
  tau_HT_KBCBPS = mean(data[,1]*RKHS_fit1$w) - mean(data[,1]*RKHS_fit0$w)
  tau_Hajek_KBCBPS = sum(data[,1]*RKHS_fit1$w)/sum(RKHS_fit1$w) - 
    sum(data[,1]*RKHS_fit0$w)/sum(RKHS_fit0$w)
  c(tau_HT_KBCBPS, tau_Hajek_KBCBPS)
}
apply(Model1_KBCBPS, 2, mean)
Model1_n1 = cbind(Model1, Model1_KBCBPS)
bias_n1 = apply(Model1_n1, 2, mean) - 10
bias_n1
var_n1 = apply(Model1_n1, 2, var)
var_n1
rmse_n1 = sqrt(bias_n1^1 + var_n1)
rmse_n1
table1 = rep(0, 20)
for (i in 1:10) {
  table1[2*i-1] = bias_n1[i]
  table1[2*i] = rmse_n1[i]
}
table_n1 = matrix(table1, nrow = 5, byrow = TRUE)

## True Model 1 when n = 500
Model1_n2_1 = foreach(B = 1:1000, .combine = 'rbind') %dopar% {
  n = 500
  set.seed(1000+B)
  data_raw = data_simu_M1[sample.int(nrow(data_simu_M1), n, replace = F), ]  # sample 200 rows from data_simu
  
  ######################
  ### GFPLM Fitting ####
  ######################
  
  data = cbind(data_raw[,1:5], FPCA(data_raw[,6:ncol(data_raw)])) # combine Y,T,W,PC scores of X
  Ncol = ncol(data)
  glmFit = glm(data[,2] ~ data[,3:Ncol], family = 'binomial')
  p_hat_glm = predict(glmFit, type = "response") # Be careful when some p_hat = 0
  
  tau_HT_glm  = mean(data[,1]*data[,2]/p_hat_glm - data[,1]*(1-data[,2])/(1-p_hat_glm))
  tau_Hajek_glm = (sum(data[,1]*data[,2]/p_hat_glm)/sum(data[,2]/p_hat_glm) - 
                     sum(data[,1]*(1-data[,2])/(1-p_hat_glm))/sum((1-data[,2])/(1-p_hat_glm)))
  
  ######################
  #### FGAM Fitting ####
  ######################
  
  S = matrix(rep(seq(0,1,length = 51), n), nrow = n)
  gamFit = gam(data_raw[, 2] ~ data_raw[, 3:5] + 
                 te(data_raw[, 6:ncol(data_raw)], S, bs = 'cr',
                    k = c(7, 7), m = list(c(2, 1), c(2, 1))), family = 'binomial')
  p_hat_gam = predict(gamFit, type = "response") # Be careful when some p_hat = 0
  
  tau_HT_gam    = mean(data[,1]*data[,2]/p_hat_gam - data[,1]*(1-data[,2])/(1-p_hat_gam))
  tau_Hajek_gam = sum(data[,1]*data[,2]/p_hat_gam)/sum(data[,2]/p_hat_gam) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_gam))/sum((1-data[,2])/(1-p_hat_gam))
  
  
  
  ######################
  ######  CBPS  ########
  ######################
  
  CBPSFit1 = CBPS(data[, 2] ~ data[, 3:Ncol], ATT = 0)
  p_hat_CBPS1 = CBPSFit1$fitted.values
  tau_HT_CBPS1    = mean(data[,1]*data[,2]/p_hat_CBPS1 - data[,1]*(1-data[,2])/(1-p_hat_CBPS1))
  tau_Hajek_CBPS1 = sum(data[,1]*data[,2]/p_hat_CBPS1)/sum(data[,2]/p_hat_CBPS1) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_CBPS1))/sum((1-data[,2])/(1-p_hat_CBPS1))
  
  
  
  X_CBPS2 = cbind(data[, 3:Ncol],data[, 3:Ncol]^2)
  CBPSFit2 = CBPS(data[, 2] ~ X_CBPS2, ATT = 0)
  p_hat_CBPS2 = CBPSFit2$fitted.values
  tau_HT_CBPS2   = mean(data[,1]*data[,2]/p_hat_CBPS2 - data[,1]*(1-data[,2])/(1-p_hat_CBPS2))
  tau_Hajek_CBPS2 = sum(data[,1]*data[,2]/p_hat_CBPS2)/sum(data[,2]/p_hat_CBPS2) - 
    sum(data[,1]*(1-data[,2])/(1-p_hat_CBPS2))/sum((1-data[,2])/(1-p_hat_CBPS2))
  
  c(tau_HT_glm,tau_Hajek_glm, tau_HT_gam, tau_Hajek_gam, tau_HT_CBPS1, tau_Hajek_CBPS1,
    tau_HT_CBPS2, tau_Hajek_CBPS2) #tau_HT_KBCBPS, tau_Hajek_KBCBPS
}

apply(Model1_n2_1, 2, mean)

Model1_n2_2 = foreach(B = 1:1000, .combine = 'rbind') %dopar% {
  n = 500
  set.seed(1000+B)
  data_raw = data_simu_M1[sample.int(nrow(data_simu_M1), n, replace = F), ]  # sample 200 rows from data_simu
  data = cbind(data_raw[,1:5], FPCA(data_raw[,6:ncol(data_raw)])) # combine Y,T,W,PC scores of X
  Ncol = ncol(data)
  data_std <- transform.sob(data[, 3:Ncol])$Xstd # standardize X to [0,1]^p
  K <- getGram(data_std) # get Gram matrix using Sobolev kernel
  
  # design a grid for the tuning parameter
  nlam <- 50
  lams <- exp(seq(log(1e-8), log(1), len=nlam))
  
  # compute weights for T=1
  RKHS_fit1 <- ATE.ncb.SN(data[,2], K, lam1s=lams)
  if (sum(RKHS_fit1$warns)) cat("lambda bound warning!\n")
  
  
  #### T=0 ####
  
  # compute weights for T=0
  RKHS_fit0 <- ATE.ncb.SN(1-data[,2], K, lam1s=lams)
  if (sum(RKHS_fit0$warns)) cat("lambda bound warning!\n")
  
  tau_HT_KBCBPS = mean(data[,1]*RKHS_fit1$w) - mean(data[,1]*RKHS_fit0$w)
  tau_Hajek_KBCBPS = sum(data[,1]*RKHS_fit1$w)/sum(RKHS_fit1$w) - 
    sum(data[,1]*RKHS_fit0$w)/sum(RKHS_fit0$w)
  c(tau_HT_KBCBPS, tau_Hajek_KBCBPS)
}










