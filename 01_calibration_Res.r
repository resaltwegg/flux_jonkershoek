# R script fitting state-space models to Jonkershoek flux data
# Res Altwegg
# 23 July 2025

library(rjags)
library(ecoforecastR)
library(tidyverse)

# Read data and clean them using a helper function.
ecdat <- ingest_and_qa()

# pick a subset (one month)
ecdat_sub <- ecdat[ecdat$month=='03' & ecdat$year=='2022',]

hist(ecdat_sub$Fc_molar)

# plot the data
#pdf("March2023.pdf",8,4)
plot(ecdat_sub$time,ecdat_sub$Fc_molar, type='l')
#dev.off()


# fit the random walk model
# ************************

RandomWalk = "
model{

  #### Data Model
  for(t in 1:n){
    y[t] ~ dnorm(x[t],tau_obs)
  }

  #### Process Model
  for(t in 2:n){
    x[t]~dnorm(x[t-1],tau_add)
  }

  #### Priors
  x[1] ~ dnorm(x_ic,tau_ic)
  tau_obs ~ dgamma(a_obs,r_obs)
  tau_add ~ dgamma(a_add,r_add)
}
"

y <- ecdat_sub$Fc_molar
y[-(1:(48*14))] <- NA # response variable we want to model (take first 14 days)
y[is.nan(y)] <- NA

data <- list(y=y,n=length(y),      ## data
               x_ic=0,tau_ic=0.1, ## initial condition prior
               a_obs=1,r_obs=1,           ## obs error prior
               a_add=1,r_add=1            ## process error prior
)

nchain = 3
init <- list()
for(i in 1:nchain){
  y.samp = sample(y,length(y),replace=TRUE)
  init[[i]] <- list(tau_add=1/var(diff(y.samp, na.rm=T), na.rm=T),  ## initial guess on process precision
                    tau_obs=5/var(y.samp, na.rm=T))        ## initial guess on obs precision
}

j.model   <- jags.model (file = textConnection(RandomWalk),
                           data = data,
                           inits = init,
                           n.chains = nchain)

jags.out   <- coda.samples (model = j.model,
                            variable.names = c("tau_add","tau_obs"),
                            n.iter = 1000)
plot(jags.out)
dic.samples(j.model, 2000)
gelman.diag(jags.out)

jags.out   <- coda.samples (model = j.model,
                              variable.names = c("x","tau_add","tau_obs"),
                              n.iter = 1000)

save(jags.out,file = "jagsoutput_randomwalk.Rdata")


time.rng = c(1,length(ecdat_sub$time))       ## adjust to zoom in and out
out <- as.matrix(jags.out)         ## convert from coda to matrix
x.cols <- grep("^x",colnames(out)) ## grab all columns that start with the letter x
ci_randomwalk <- apply(out[,x.cols],2,quantile,c(0.025,0.5,0.975)) ## model was fit on log scale


# plot time series and fitted model

plot_ts <- function(){
time.rng = c(1,length(ecdat_sub$time))       ## adjust to zoom in and out
out <- as.matrix(jags.out)         ## convert from coda to matrix
x.cols <- grep("^x",colnames(out)) ## grab all columns that start with the letter x
ci <- apply(out[,x.cols],2,quantile,c(0.025,0.5,0.975)) ## model was fit on log scale

plot(Fc_molar~time,type='n',ylim=range(y,na.rm=TRUE),ylab="NEE",xlim=time[time.rng], data=ecdat_sub)
## adjust x-axis label to be monthly if zoomed
if(diff(time.rng) < 100){
  axis.Date(1, at=seq(time[time.rng[1]],time[time.rng[2]],by='month'), format = "%Y-%m")
}
ecoforecastR::ciEnvelope(ecdat_sub$time,ci[1,],ci[3,],col=ecoforecastR::col.alpha("lightBlue",0.75))

points(ecdat_sub$time,ecdat_sub$Fc_molar,pch="+",cex=0.5, col=c(rep("black", 48*14), rep("red", length(y)-(48*14))))
lines(ecdat_sub$time,ci[2,])
}

pdf("March2022_random_walk.pdf",8,4)
plot_ts()
dev.off()


# fit model with temperature and light
# ************************************

TempLight_model = "
model{

  #### Data Model
  for(t in 1:n){
    y[t] ~ dnorm(x[t],tau_obs)
  }

  #### Process Model
  for(t in 2:n){
    x[t] <- rho * x[t-1] + b1 * light[t] + b2*temperature[t] + alpha[t-1]
#    x[t]~dnorm(x[t-1],tau_add)
  }

  #### Priors
  x[1] ~ dnorm(0,0.1)  # initial condition
  tau_obs ~ dgamma(1,1)  # observation error
  for (i in 1:(n-1)) {alpha[i] ~ dnorm(0,tau_add)}
  tau_add ~ dgamma(1,1) # process error
  rho ~ dunif(-1,1)  # autocorrelation
  b1 ~ dnorm(0,0.1) # coefficient for light
  b2 ~ dnorm(0,0.1)  # coefficient for temperature
}
"

y <- ecdat_sub$Fc_molar
y[-(1:(48*14))] <- NA # response variable we want to model (take first 14 days)
y[is.nan(y)] <- NA

light <- ecdat_sub$Rn
light[is.na(light)] <- mean(light)

temperature <- ecdat_sub$Tc_Avg
temperature[is.na(temperature)] <- mean(temperature)

data <- list(y=y,n=length(y),      ## data
             light=light,
             temperature=ecdat_sub$Tc_Avg
)

nchain = 3
init <- list()
for(i in 1:nchain){
  y.samp = sample(y,length(y),replace=TRUE)
  init[[i]] <- list(tau_add=1,  ## initial guess on process precision
                    tau_obs=5/var(y.samp, na.rm=T))        ## initial guess on obs precision
}

j.model   <- jags.model (file = textConnection(TempLight_model),
                         data = data,
                         inits = init,
                         n.chains = nchain)

jags.out   <- coda.samples (model = j.model,
                            variable.names = c("tau_add","tau_obs","rho","b1","b2"),
                            n.iter = 1000)
plot(jags.out)
gelman.diag(jags.out)

# dic.samples(j.model, 2000)

jags.out   <- coda.samples (model = j.model,
                            variable.names = c("x","tau_add","tau_obs","rho","b1","b2"),
                            n.iter = 5000)

save(jags.out,file = "jagsoutput_temp_light.Rdata")


# plot time series and fitted model

pdf("March2022_temp_light.pdf",8,4)
plot_ts()
dev.off()

# Extract CI from the output matrix from jags.out
summary(jags.out)

out.matrix <- as.matrix(jags.out) 

ci_statespace <- apply(out.matrix[,grep("^x",colnames(out.matrix))],2,quantile,c(0.025,0.5,0.975)) ## get ci  from the matrix
t(ci_statespace)

# # # # 

# Form validation datasets ************

# Randomwalk
pred_obs_df_randomwalk = as.data.frame(t(ci_randomwalk), row.names = F) %>%
  rename(pi_lower = "2.5%", predicted_NEE = "50%", pi_upper = "97.5%") %>%
  mutate(time = ecdat_sub$time,
         doy = ecdat_sub$doy,
         hod = ecdat_sub$hod,
         Fc_molar_obs = ecdat_sub$Fc_molar)

val_df_randomwalk = pred_obs_df_randomwalk[-(1:(48*14)),] %>%
  select(time, doy, hod, Fc_molar_obs, predicted_NEE, pi_lower, pi_upper)

val_df_randomwalk$Within_PI = val_df_randomwalk$pi_upper >= val_df_randomwalk$Fc_molar_obs & val_df_randomwalk$Fc_molar_obs >= val_df_randomwalk$pi_lower 

(Error_Summary_randomwalk <- val_df_randomwalk %>%
    summarise(
      N = n(),
      MAE = mean(abs(predicted_NEE - Fc_molar_obs), na.rm = TRUE),
      MSE = mean((predicted_NEE - Fc_molar_obs)^2, na.rm = TRUE),
      RMSE = sqrt(mean((predicted_NEE - Fc_molar_obs)^2, na.rm = TRUE)),
      Coverage_90 = mean(Within_PI, na.rm = TRUE)
    ))

# Timelight
pred_obs_df_timelight = as.data.frame(t(ci_statespace), row.names = F) %>%
  rename(pi_lower = "2.5%", predicted_NEE = "50%", pi_upper = "97.5%") %>%
  mutate(time = ecdat_sub$time,
         doy = ecdat_sub$doy,
         hod = ecdat_sub$hod,
         Fc_molar_obs = ecdat_sub$Fc_molar)

val_df_timelight = pred_obs_df_timelight[-(1:(48*14)),] %>%
  select(time, doy, hod, Fc_molar_obs, predicted_NEE, pi_lower, pi_upper)

val_df_timelight$Within_PI = val_df_timelight$pi_upper >= val_df_timelight$Fc_molar_obs & val_df_timelight$Fc_molar_obs >= val_df_timelight$pi_lower 

(Error_Summary_timelight <- val_df_timelight %>%
    summarise(
      N = n(),
      MAE = mean(abs(predicted_NEE - Fc_molar_obs), na.rm = TRUE),
      MSE = mean((predicted_NEE - Fc_molar_obs)^2, na.rm = TRUE),
      RMSE = sqrt(mean((predicted_NEE - Fc_molar_obs)^2, na.rm = TRUE)),
      Coverage_90 = mean(Within_PI, na.rm = TRUE)
    ))

# Climatology

val_df_climatology = climatology_pred %>%
  filter(doy %in% unique(val_df_timelight$doy)) %>%
  left_join(val_df_timelight[,c("time","doy", "hod", "Fc_molar_obs")], by = c("doy", "hod")) %>%
  mutate(pi_upper = predicted_NEE + 1.96*sqrt(mean((val_df_climatology$predicted_NEE - val_df_climatology$Fc_molar_obs)^2, na.rm = TRUE)),
         pi_lower = predicted_NEE - 1.96*sqrt(mean((val_df_climatology$predicted_NEE - val_df_climatology$Fc_molar_obs)^2, na.rm = TRUE))) %>%
  select(time, doy, hod, Fc_molar_obs, predicted_NEE, ci_lower, ci_upper, pi_lower, pi_upper)

val_df_climatology$Within_PI = val_df_climatology$pi_upper >= val_df_climatology$Fc_molar_obs & val_df_climatology$Fc_molar_obs >= val_df_climatology$pi_lower 

(Error_Summary_climatology <- val_df_climatology %>%
    summarise(
      N = n(),
      MAE = mean(abs(predicted_NEE - Fc_molar_obs), na.rm = TRUE),
      MSE = mean((predicted_NEE - Fc_molar_obs)^2, na.rm = TRUE),
      RMSE = sqrt(mean((predicted_NEE - Fc_molar_obs)^2, na.rm = TRUE)),
      Coverage_90 = mean(Within_PI, na.rm = TRUE)
    ))

# Out of sample prediction plots ***********

# randomwalk
ggplot(val_df_randomwalk, aes(x = time)) +
  geom_ribbon(aes(ymin = pi_lower, ymax = pi_upper),
              fill = "lightblue", alpha = 0.5) +
  geom_line(aes(y = predicted_NEE), color = "black", size = 0.5, alpha = 0.5) +
  geom_point(aes(y = Fc_molar_obs), color = "red", size = 0.5, alpha = 0.7) +
  labs(
    title = "Randomwalk model out-of-sample predictions",
    x = "Date",
    y = "NEE (µmol/m²/s)"
  ) +
  theme_classic()

ggsave("./img/Randomwalk_out_of_sample_predictions.png",
       width = 17,
       height = 12,
       units = "cm",
       dpi = 300)

# climatology
ggplot(val_df_climatology, aes(x = time)) +
  geom_ribbon(aes(ymin = pi_lower, ymax = pi_upper),
              fill = "lightblue", alpha = 0.5) +
  geom_line(aes(y = predicted_NEE), color = "black", size = 0.5, alpha = 0.5) +
  geom_point(aes(y = Fc_molar_obs), color = "red", size = 0.5, alpha = 0.7) +
  labs(
    title = "Climatology model out-of-sample predictions",
    x = "Date",
    y = "NEE (µmol/m²/s)"
  ) +
  theme_classic()

ggsave("./img/GAM_Climatology_out_of_sample_predictions.png",
       width = 17,
       height = 12,
       units = "cm",
       dpi = 300)

# timelight
ggplot(val_df_timelight, aes(x = time)) +
  geom_ribbon(aes(ymin = pi_lower, ymax = pi_upper),
              fill = "lightblue", alpha = 0.5) +
  geom_line(aes(y = predicted_NEE), color = "black", size = 0.5, alpha = 0.5) +
  geom_point(aes(y = Fc_molar_obs), color = "red", size = 0.5, alpha = 0.7) +
  labs(
    title = "Dynamic state-space model out-of-sample predictions",
    x = "Date",
    y = "NEE (µmol/m²/s)"
  ) +
  theme_classic()

ggsave("./img/dynamic_state_space_out_of_sample_predictions.png",
       width = 17,
       height = 12,
       units = "cm",
       dpi = 300)


# Scatter Plot with Prediction Intervals ************

# Randomwalk
ggplot(val_df_randomwalk, aes(x = Fc_molar_obs, y = predicted_NEE, colour = Within_PI)) +
  geom_point(size = 2) +
  geom_linerange(aes(ymin = pi_lower, ymax = pi_upper)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "black", "FALSE" = "red"), guide = "none") +
  scale_x_continuous(
    limits = c(
      min(val_df_randomwalk$Fc_molar_obs, val_df_randomwalk$predicted_NEE, val_df_randomwalk$pi_lower, na.rm = TRUE) - 1,
      max(val_df_randomwalk$Fc_molar_obs, val_df_randomwalk$predicted_NEE, val_df_randomwalk$pi_upper, na.rm = TRUE) + 1
    )) +
  scale_y_continuous(
    limits = c(
      min(val_df_randomwalk$Fc_molar_obs, val_df_randomwalk$predicted_NEE, val_df_randomwalk$pi_lower, na.rm = TRUE) - 1,
      max(val_df_randomwalk$Fc_molar_obs, val_df_randomwalk$predicted_NEE, val_df_randomwalk$pi_upper, na.rm = TRUE) + 1
    )) +
  labs(
    title = "Randomwalk model: predicted against observed",
    x = "Fc molar observed (µmol/m²/s)",
    y = "Fc molar modelled (µmol/m²/s)"
  ) +
  theme_classic()

ggsave("./img/Randomwalk_predicted_versus_observed.png",
       width = 17,
       height = 12,
       units = "cm",
       dpi = 300)

# Climatology
ggplot(val_df_climatology, aes(x = Fc_molar_obs, y = predicted_NEE, colour = Within_PI)) +
  geom_point(size = 2) +
  geom_linerange(aes(ymin = pi_lower, ymax = pi_upper)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "black", "FALSE" = "red"), guide = "none") +
  scale_x_continuous(
    limits = c(
      min(val_df_climatology$Fc_molar_obs, val_df_climatology$predicted_NEE, val_df_climatology$pi_lower, na.rm = TRUE) - 1,
      max(val_df_climatology$Fc_molar_obs, val_df_climatology$predicted_NEE, val_df_climatology$pi_upper, na.rm = TRUE) + 1
    )) +
  scale_y_continuous(
    limits = c(
      min(val_df_climatology$Fc_molar_obs, val_df_climatology$predicted_NEE, val_df_climatology$pi_lower, na.rm = TRUE) - 1,
      max(val_df_climatology$Fc_molar_obs, val_df_climatology$predicted_NEE, val_df_climatology$pi_upper, na.rm = TRUE) + 1
    )) +
  labs(
    title = "Climatology model: predicted against observed",
    x = "Fc molar observed (µmol/m²/s)",
    y = "Fc molar modelled (µmol/m²/s)"
  ) +
  theme_classic()

ggsave("./img/GAM_Climatology_predicted_versus_observed.png",
       width = 17,
       height = 12,
       units = "cm",
       dpi = 300)


# timelight
ggplot(val_df_timelight, aes(x = Fc_molar_obs, y = predicted_NEE, colour = Within_PI)) +
  geom_point(size = 2) +
  geom_linerange(aes(ymin = pi_lower, ymax = pi_upper)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "black", "FALSE" = "red"), guide = "none") +
  scale_x_continuous(
    limits = c(
      min(val_df_timelight$Fc_molar_obs, val_df_timelight$predicted_NEE, val_df_timelight$pi_lower, na.rm = TRUE) - 1,
      max(val_df_timelight$Fc_molar_obs, val_df_timelight$predicted_NEE, val_df_timelight$pi_upper, na.rm = TRUE) + 1
    )) +
  scale_y_continuous(
    limits = c(
      min(val_df_timelight$Fc_molar_obs, val_df_timelight$predicted_NEE, val_df_timelight$pi_lower, na.rm = TRUE) - 1,
      max(val_df_timelight$Fc_molar_obs, val_df_timelight$predicted_NEE, val_df_timelight$pi_upper, na.rm = TRUE) + 1
    )) +
  labs(
    title = "Dynamic state-space model: predicted against observed",
    x = "Fc molar observed",
    y = "Fc molar modelled"
  ) +
  theme_classic()

ggsave("./img/dynamic_state_space_predicted_versus_observed.png",
       width = 17,
       height = 12,
       units = "cm",
       dpi = 300)