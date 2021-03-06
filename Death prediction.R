#preparation
library(dplyr)
library(ranger)
library(xgboost)
library(caret)
library(SDMTools)
library(e1071)
library(cvTools)
library(randomForest)
library(lubridate)
library(pROC)
library(rpart)

#retrieve data
total <- read.csv('D:/development/stroke/data/StrokeData_MayUpdate.csv', na.strings = c("", "NA"), stringsAsFactors = F)

#Exploratory data analysis
str(total)
colnames(total)[colSums(is.na(total)) > 0]
summary(total$EDHour) # NA's :5
summary(total$MinstoRad) # NA's : 171
summary(total$NIHSS) #NA's : 373


#remove some columns
total <- total %>% select(-NHI,-IP_Encounter,-Dependence_Level,-AcuteLOS,-Rehab,-RehabLOS,-TotalLOS, -AssessedByStrokeTeam)
total <- total[,order(colnames(total))]

#feature engineering
total$admitdate <- as.Date(total$admitdate, "%d/%m/%Y")
total$InptDeath <- as.factor(total$InptDeath) 
total$month <- month(total$admitdate)
total$daydiff <- as.numeric(Sys.Date()-total$admitdate)
total$admitdate <- NULL
total$Ethnicity <- as.factor(total$Ethnicity)
total$TriageCode <- as.factor(total$TriageCode)
total$FiscalYear <- NULL
total$weight <- 1/total$daydiff

#remove some outstanding outliers (univariate approach)
total <- total %>% filter(MinstoRad < 1e+05)
total <- total %>% filter(IPEventsLast6Mths < 20)

#NA handling
without_na <- total[complete.cases(total), ]
without_na <- without_na %>% select(-InptDeath, -weight)
colnames(without_na)[colSums(is.na(without_na)) > 0]



#impute NA for NIHSS

prod.params <- list(mtry = 5, nodesize = 13) 
set.seed(1234)
model <- ranger(formula = NIHSS~. ,
                data=without_na,
                num.trees = 25,
                mtry=prod.params$mtry,
                min.node.size = prod.params$nodesize)



total[which(is.na(total$NIHSS)), "NIHSS"] <- predictions(predict(model, total))[which(is.na(total$NIHSS))]

##impute NA for MinstoRad
#set.seed(1234)
#model <-randomForest(MinstoRad~. , without_na)
#total[which(is.na(total$MinstoRad)), "MinstoRad"] <- predict(model, total)[which(is.na(total$MinstoRad))]
#
##impute NA for EDHour
#set.seed(1234)
#model <-randomForest(EDHour~. , without_na)
#total[which(is.na(total$EDHour)), "EDHour"] <- predict(model, total)[which(is.na(total$EDHour))]
#
##impute NA for NIHSS
#without_na <- total[complete.cases(total), ]
#without_na <- without_na %>% select(-InptDeath, -weight, -MinstoRad, -EDHour)
#colnames(without_na)[colSums(is.na(without_na)) > 0]
#set.seed(1234)
#model <-randomForest(NIHSS~. , without_na)
#total[which(is.na(total$NIHSS)), "NIHSS"] <- predict(model, total)[which(is.na(total$NIHSS))]
#
##impute NA for MinstoRad
#without_na <- total[complete.cases(total), ]
#without_na <- without_na %>% select(-InptDeath, -weight, -NIHSS, -EDHour)
#colnames(without_na)[colSums(is.na(without_na)) > 0]
#set.seed(1234)
#model <-randomForest(MinstoRad~. , without_na)
#total[which(is.na(total$MinstoRad)), "MinstoRad"] <- predict(model, total)[which(is.na(total$MinstoRad))]
#
##impute NA for EDHour
#without_na <- total[complete.cases(total), ]
#without_na <- without_na %>% select(-InptDeath, -weight, -NIHSS, -MinstoRad)
#colnames(without_na)[colSums(is.na(without_na)) > 0]
#set.seed(1234)
#model <-randomForest(EDHour~. , without_na)
#total[which(is.na(total$EDHour)), "EDHour"] <- predict(model, total)[which(is.na(total$EDHour))]
#
#total$NIHSS <- round(total$NIHSS)
#total$MinstoRad <- round(total$MinstoRad)
#total$EDHour <- round(total$EDHour)

#split the data
set.seed(54321)
outcome <- total$InptDeath

partition <- createDataPartition(y=outcome,
                                 p=.75,
                                 list=F)
train <- total[partition,]
test <- total[-partition,]


#4 fold cross validation without outlier handling
set.seed(1234)
cross <- cvFolds(nrow(train), K=4)
cnt = 1
acc <- numeric()

for(i in 1:4){
  datas_idx <- cross$subsets[cross$which==i,1]
  
  testing <- train[datas_idx,]
  training <- train[-datas_idx,]
  
  prod.params <- list(mtry = 5, nodesize = 13) 
  set.seed(1234)
  model <- ranger(formula = InptDeath~.-weight,
                  data=training,
                  num.trees = 25,
                  mtry=prod.params$mtry,
                  min.node.size = prod.params$nodesize)
  
  prediction <- predictions(predict(model, testing))
  
  
  acc[cnt] <- confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]]
  cnt <- cnt + 1}

mean(acc) #0.9300442

#evaluation with test set without outlier handling
prod.params <- list(mtry = 5, nodesize = 13) 
set.seed(1234)
rf_model <- ranger(formula = InptDeath~.-weight,
                   data=train,
                   num.trees = 25,
                   mtry=prod.params$mtry,importance = 'impurity',
                   min.node.size = prod.params$nodesize)

#evaluation
prediction <- predictions(predict(rf_model, test))
confusionMatrix(prediction, test$InptDeath)[["overall"]][["Accuracy"]] #I got 0.9279609




#
##outlier handling
#library("cluster")
#set.seed(123)
#km.res <- kmeans(train %>% select(-InptDeath), 2, nstart = 25)
#
#train$cluster <- as.vector(km.res$cluster)
#train$cluster <- as.factor(train$cluster)
#
#
#train <- train %>% filter(cluster == 1)
#train <- train %>% select(-cluster)
#
##evaluation
##4 fold cross validation
#set.seed(1234)
#cross <- cvFolds(nrow(train), K=4)
#cnt = 1
#acc <- numeric()
#
#for(i in 1:4){
#  datas_idx <- cross$subsets[cross$which==i,1]
#  
#  testing <- train[datas_idx,]
#  training <- train[-datas_idx,]
#  
#  prod.params <- list(mtry = 5, nodesize = 13) 
#  set.seed(1234)
#  model <- ranger(formula = InptDeath~.-weight,
#                  data=training,
#                  num.trees = 25,
#                  mtry=prod.params$mtry,
#                  min.node.size = prod.params$nodesize)
#  
#  prediction <- predictions(predict(model, testing))
#  
#  
#  acc[cnt] <- confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]]
#  cnt <- cnt + 1}
#
#mean(acc) #0.9317129




#evaluation with test set
#
#prod.params <- list(mtry = 5, nodesize = 13) 
#set.seed(1234)
#rf_model <- ranger(formula = InptDeath~.-weight,
#                   data=train,
#                   num.trees = 25,
#                   mtry=prod.params$mtry,importance = 'impurity',
#                   min.node.size = prod.params$nodesize)
#
#
#prediction <- predictions(predict(rf_model, test))
#confusionMatrix(prediction, test$InptDeath)[["overall"]][["Accuracy"]] #I got 0.9430524







#finding optimized tuned weight

set.seed(1234)
cross <- cvFolds(nrow(train), K=4)

comparison <- data.frame(int =1:30)
c=2

for(i in 1:4){
  datas_idx <- cross$subsets[cross$which==i,1]
  
  testing <- train[datas_idx,]
  training <- train[-datas_idx,]
  
  
  
  
  #finding optimized tuned weight
  weight.comparison <- data.frame(int = numeric(), accuracy = numeric())
  for(n in 1:30){
    
    #evaluation with using weight
    
    tuned.weight <- (training$weight + (1.5^n)/100)/max(training$weight + (1.5^n)/100)
    
    set.seed(1234)
    prod.params <- list(mtry = 5, nodesize = 13) 
    
    rf_model1 <- ranger(formula = InptDeath~.-weight ,
                        data=training,
                        num.trees = 25,
                        mtry=prod.params$mtry, 
                        case.weights = tuned.weight,
                        min.node.size = prod.params$nodesize)
    
    #evaluation
    prediction <- predictions(predict(rf_model1, testing))
    print(confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]])
    result <- data.frame(int = n, accuracy = confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]])
    weight.comparison <- rbind(weight.comparison,result)}
  
  comparison[c] <- weight.comparison$accuracy
  c <- c + 1
  
}

comparison$average <- (comparison$V2 + comparison$V3 + comparison$V4 + comparison$V5)/4
comparison <- comparison %>% arrange(desc(average))
max(comparison$average) #0.9328898

#choosing the n
tuned.weight <- (train$weight + (1.5^comparison[1,1])/100)/max(train$weight + (1.5^comparison[1,1])/100)
train$weight <- tuned.weight

#accuracy for test
set.seed(1234)
prod.params <- list(mtry = 20, nodesize = 13) 

rf_model1 <- ranger(formula = InptDeath~. -weight,
                    data=train,
                    num.trees = 25,
                    mtry=prod.params$mtry, 
                    case.weights = train$weight,
                    min.node.size = prod.params$nodesize)

#evaluation
prediction <- predictions(predict(rf_model1, test))
print(confusionMatrix(prediction, test$InptDeath)[["overall"]][["Accuracy"]]) #0.9401709

#feature selection from ranger : importance = 'impurity'
prod.params <- list(mtry = 5, nodesize = 13) 
set.seed(1234)
rf_model <- ranger(formula = InptDeath~.-weight,
                   data=train,
                   num.trees = 25,
                   mtry=prod.params$mtry,importance = 'impurity',
                   case.weights = train$weight,
                   min.node.size = prod.params$nodesize)

v<-as.vector(rf_model$variable.importance)
train1 <- train %>% select(-InptDeath,-weight)
w <- colnames(train1)
DF<-cbind(w,v)
DF<-as.data.frame(DF)
DF$v <- as.character(DF$v)
DF$v <- as.numeric(DF$v)

feature.importance <- DF %>% arrange(v)

#plot feature importance
library(ggplot2)
imp_matrix <- DF %>% arrange(desc(v))
imp_matrix %>%
  ggplot(aes(reorder(w, v, FUN = max), v, fill = w)) +
  geom_col() +
  coord_flip() +
  theme(legend.position = "none") +
  labs(x = "Features", y = "Importance")




#finding optimized number of features

set.seed(1234)
cross <- cvFolds(nrow(train), K=4)
cnt = 1
acc <- numeric()
comparison <- data.frame(int =1:20)
c=2

for(i in 1:4){
  datas_idx <- cross$subsets[cross$which==i,1]
  
  testing <- train[datas_idx,]
  training <- train[-datas_idx,]
  
  col.remove <- data.frame(int = numeric(), accuracy = numeric())
  for(n in 1:20){
    
    fi <- feature.importance[-c(1:n),]
    
    fi <- as.vector(fi[,1])
    
    #feature selection
    training <- training[,c('InptDeath',fi)]
    testing <- testing[,c('InptDeath',fi)]
    
    set.seed(1234)
    prod.params <- list(mtry = 10, nodesize = 13) 
    
    rf_model1 <- ranger(formula = InptDeath~. -weight,
                        data=training,
                        num.trees = 25,
                        mtry=prod.params$mtry, 
                        case.weights = training$weight,
                        min.node.size = prod.params$nodesize)
    
    #evaluation
    prediction <- predictions(predict(rf_model1, testing))
    print(confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]])
    result <- data.frame(int = n, accuracy = confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]])
    col.remove <- rbind(col.remove,result)
  }
  
  comparison[c] <- col.remove$accuracy
  c <- c + 1
  
}

comparison$average <- (comparison$V2 + comparison$V3 + comparison$V4 + comparison$V5)/4
comparison <- comparison %>% arrange(desc(average))
b <- max(comparison$average) #0.9320794

important_features <- feature.importance[-c(1:comparison[1,1]),]
important_features <- as.vector(important_features[,1])

#evaluate with test set
train1 <- train[,c('InptDeath','weight',important_features)]
train1 <- train1[,order(colnames(train1))]

prod.params <- list(mtry = 5, nodesize = 13) 

set.seed(1234)
rf_model <- ranger(formula = InptDeath~.-weight,
                   data=train1,
                   num.trees = 25,
                   mtry=prod.params$mtry,importance = 'impurity',
                   case.weights = train1$weight,
                   min.node.size = prod.params$nodesize)

#evaluation
prediction <- predictions(predict(rf_model, test))
confusionMatrix(prediction, test$InptDeath)[["overall"]][["Accuracy"]] #0.9340659 / including rehab:0.9453303

#Reducing train_data and test_data by selecting important features
train <- train[,c('InptDeath','weight',important_features)]
test <- test[,c('InptDeath','weight',important_features)]
train <- train[,order(colnames(train))]
test <- test[,order(colnames(test))]

#Ranger parameter tuning
tune.grid <- expand.grid(mtry = 1:(ncol(train)-2),
                         nodesize = 1:(ncol(train)-2))
set.seed(1234)
cross <- cvFolds(nrow(train), K=4)
comparison <- data.frame(int =  1:nrow(tune.grid))
c=2

for(i in 1:4){
  datas_idx <- cross$subsets[cross$which==i,1]
  
  testing <- train[datas_idx,]
  training <- train[-datas_idx,]
  
  a <- data.frame(int = numeric(), accuracy = numeric())
  for(n in 1:nrow(tune.grid)) {
    prod.params <- list(mtry = as.numeric(tune.grid[n,'mtry']), 
                        nodesize = as.numeric(tune.grid[n,'nodesize']))
    
    set.seed(1234)
    rf_model <- ranger(formula = InptDeath~.-weight,
                       data=training,
                       num.trees = 50,
                       mtry=prod.params$mtry,
                       case.weights = training$weight,
                       min.node.size = prod.params$nodesize)
    
    #evaluation
    prediction <- predictions(predict(rf_model, testing))
    print(confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]])
    
    result <- data.frame(grid.number = n, accuracy = confusionMatrix(prediction, testing$InptDeath)[["overall"]][["Accuracy"]])
    a <- rbind(a,result)
  }
  
  comparison[c] <- a$accuracy
  c <- c + 1
  
} 

comparison$average <- (comparison$V2 + comparison$V3 + comparison$V4 + comparison$V5)/4
comparison <- comparison %>% arrange(desc(average))
max(comparison$average) #0.9328917

prod.params <- list(mtry = as.numeric(tune.grid[comparison[1,1],'mtry']), 
                    nodesize = as.numeric(tune.grid[comparison[1,1],'nodesize']))
#5/6

#using test to evaluate

set.seed(1234)
death_predictor <- ranger(formula = InptDeath~.-weight,
                          data=train,
                          num.trees = 50,
                          mtry=prod.params$mtry,importance = 'impurity',
                          case.weights = train$weight,
                          min.node.size = prod.params$nodesize)

#evaluation
prediction_rf <- predictions(predict(death_predictor, test))
confusionMatrix(prediction_rf, test$InptDeath)[["overall"]][["Accuracy"]] #0.9426129
roc_obj <- roc(as.numeric(test$InptDeath), as.numeric(prediction_rf))
auc(roc_obj)


#save death_predictor
save(death_predictor, file = "D:/development/Stroke/Model/death_predictor.rda")



#multivariate outlier checking
#train$InptDeath <- as.numeric(as.character(train$InptDeath))
#test$InptDeath <- as.numeric(as.character(test$InptDeath))
#
##evaluation with test set without outlier handling
#prod.params <- prod.params
#set.seed(1234)
#rf_model <- ranger(formula = InptDeath~.-weight,
#                   data=train,
#                   num.trees = 50,
#                   mtry=prod.params$mtry,importance = 'impurity',
#                   min.node.size = prod.params$nodesize)
#
##evaluation
#prediction <- predictions(predict(rf_model, test))
#prediction <- ifelse(prediction < 0.5 , 0 ,1)
#confusionMatrix(as.factor(prediction), as.factor(test$InptDeath))[["overall"]][["Accuracy"]] #I got 0.9384966
#
#
#
#
##multivariate outlier checking
#
#prediction <- predictions(predict(rf_model, train))
#
#
##adding diff variable (Actual - prediction)^2
#train$diff <- (prediction <- predictions(predict(rf_model, train)) - train$InptDeath)^2
#
##Finding optimized quantile
#outlier.checking <- data.frame(percentage = as.numeric(), MAE = as.numeric())
#
#for(n in 80:100){
#  
#  #removing outliers
#  train1 <- train %>% filter(diff < quantile(train$diff,0.01*n))
#  train1$diff <- NULL
#  
#  
#  #outlier checking with Ranger
#  set.seed(1234)
#  prod.params <- prod.params 
#  
#  rf_model1 <- ranger(formula = InptDeath~.,
#                      data=train1,
#                      num.trees = 50,
#                      mtry=prod.params$mtry,
#                      min.node.size = prod.params$nodesize)
#  
#  
#  #evaluation
#  prediction <- predictions(predict(rf_model1, test))
#  print(mean(abs(test$InptDeath - round(prediction)), na.rm=TRUE))
#  result <- data.frame(percentage = 0.01*n, MAE = mean(abs(test$InptDeath - round(prediction)), na.rm=TRUE))
#  outlier.checking <- rbind(outlier.checking,result)}
#
##removing outliers
#outlier.checking <- outlier.checking %>% arrange(MAE)
#train <- train %>% filter(diff < quantile(train$diff,as.numeric(outlier.checking[1,1])))
#train$diff <- NULL
#
#
#
##evaluation with test set
#prod.params <- prod.params
#set.seed(1234)
#rf_model <- ranger(formula = InptDeath~.-weight,
#                   data=train,
#                   num.trees = 50,
#                   mtry=prod.params$mtry,importance = 'impurity',
#                   min.node.size = prod.params$nodesize)
#
##evaluation
#prediction <- predictions(predict(rf_model, test))
#prediction <- ifelse(prediction < 0.5 , 0 ,1)
#confusionMatrix(as.factor(prediction), as.factor(test$InptDeath))[["overall"]][["Accuracy"]] #I got 0.9362187


#using XGBoost
train1 <- train %>% select(-weight)
test1 <- test %>% select(-weight)
train1[] <- lapply(train1, as.numeric)
test1[]<-lapply(test1, as.numeric)

#xgb matrix
withoutRV <- train1 %>% select(-InptDeath)
dtrain <- xgb.DMatrix(as.matrix(withoutRV),label = train1$InptDeath-1)
withoutRV1 <- test1 %>% select(-InptDeath)
dtest <- xgb.DMatrix(as.matrix(withoutRV1))

#xgboost parameters
xgb_params <- list(colsample_bytree = 0.7, #variables per tree 
                   subsample = 0.8, #data subset per tree 
                   booster = "gbtree",
                   max_depth = 10, #tree levels
                   eta = 0.12, #shrinkage
                   objective = "binary:logistic",
                   gamma=0)    

#cross-validation and checking iterations
set.seed(4321)
xgb_cv <- xgb.cv(xgb_params,dtrain,early_stopping_rounds = 10, nfold = 4, print_every_n = 5, nrounds=1000) 

gb_dt <- xgb.train(params = xgb_params,
                   data = dtrain,
                   verbose = 1, maximize =F, 
                   nrounds = xgb_cv$best_iteration)

prediction_xgb <- predict(gb_dt,dtest)
prediction_xgb <- ifelse(prediction_xgb < 0.5 , 0 ,1)

#evaluation
confusionMatrix(as.factor(test1$InptDeath-1), as.factor(prediction_xgb))[["overall"]][["Accuracy"]] #0.9316239
roc_obj <- roc(as.numeric(test1$InptDeath)-1, as.numeric(prediction_xgb)-1)
auc(roc_obj)


#using Decision Tree

train1 <- train %>% select(-weight)
test1 <- test %>% select(-weight)


rpart <- rpart(InptDeath ~., train1)

prediction_rpart <- predict(rpart , test1, type = "class")

#evaluation
confusionMatrix(prediction_rpart, test1$InptDeath)[["overall"]][["Accuracy"]] #0.9328449
roc_obj <- roc(as.numeric(test1$InptDeath)-1, as.numeric(prediction_rpart)-1)
auc(roc_obj)

#Ensemble
training <- data.frame(rf = predictions(predict(death_predictor, train)),
                       xgb = predict(gb_dt,dtrain),
                       tree = predict(rpart,train1)[,2],
                       outcome = train$InptDeath)

testing <- data.frame(rf = predictions(predict(death_predictor, test)),
                      xgb = predict(gb_dt,dtest),
                      tree = predict(rpart,test1)[,2])

#meta learner: LM
training$outcome <- as.numeric(training$outcome)-1
ensemble <- lm(outcome ~., training)
prediction <- predict(ensemble, testing)
prediction <- ifelse(prediction < 0.5 , 0 , 1)

#evaluation
confusionMatrix(as.factor(prediction), as.factor(test$InptDeath))[["overall"]][["Accuracy"]] #0.7301587
roc_obj <- roc(as.numeric(test$InptDeath)-1, prediction)
auc(roc_obj)

#meta learniner: RF
training$outcome <- as.factor(training$outcome)
ensemble <- randomForest(formula = outcome~.,
                         data=training)
prediction <- predict(ensemble, testing)

#evaluation
confusionMatrix(prediction, as.factor(test$InptDeath))[["overall"]][["Accuracy"]] #0.7301587
roc_obj <- roc(test$InptDeath, as.numeric(prediction)-1)
auc(roc_obj)



