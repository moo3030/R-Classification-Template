# Required Libraries
library(tidyverse)
library(jsonlite)
library(fastDummies)

# Paths
ROOT_DIR <- getwd()
MODEL_INPUTS_OUTPUTS <- file.path(ROOT_DIR, 'model_inputs_outputs')
INPUT_DIR <- file.path(MODEL_INPUTS_OUTPUTS, "inputs")
OUTPUT_DIR <- file.path(MODEL_INPUTS_OUTPUTS, "outputs")
INPUT_SCHEMA_DIR <- file.path(INPUT_DIR, "schema")
DATA_DIR <- file.path(INPUT_DIR, "data")
TRAIN_DIR <- file.path(DATA_DIR, "training")
TEST_DIR <- file.path(DATA_DIR, "testing")
MODEL_PATH <- file.path(MODEL_INPUTS_OUTPUTS, "model")
MODEL_ARTIFACTS_PATH <- file.path(MODEL_PATH, "artifacts")
OHE_ENCODER_FILE <- file.path(MODEL_ARTIFACTS_PATH, 'ohe.rds')
PREDICTOR_DIR_PATH <- file.path(MODEL_ARTIFACTS_PATH, "predictor")
PREDICTOR_FILE_PATH <- file.path(PREDICTOR_DIR_PATH, "predictor.rds")
IMPUTATION_FILE <- file.path(MODEL_ARTIFACTS_PATH, 'imputation.rds')
PREDICTIONS_DIR <- file.path(OUTPUT_DIR, 'predictions')
PREDICTIONS_FILE <- file.path(PREDICTIONS_DIR, 'predictions.csv')
LABEL_ENCODER_FILE <- file.path(MODEL_ARTIFACTS_PATH, 'label_encoder.rds')
ENCODED_TARGET_FILE <- file.path(MODEL_ARTIFACTS_PATH, "encoded_target.RDS")


if (!dir.exists(PREDICTIONS_DIR)) {
  dir.create(PREDICTIONS_DIR, recursive = TRUE)
}

# Reading the schema
file_name <- list.files(INPUT_SCHEMA_DIR, pattern = "*.json")[1]
schema <- fromJSON(file.path(INPUT_SCHEMA_DIR, file_name))
features <- schema$features

numeric_features <- features$name[features$dataType != 'CATEGORICAL']
categorical_features <- features$name[features$dataType == 'CATEGORICAL']
id_feature <- schema$id$name
target_feature <- schema$target$name
target_classes <- schema$target$classes
model_category <- schema$modelCategory

# Reading test data.
file_name <- list.files(TEST_DIR, pattern = "*.csv", full.names = TRUE)[1]
df <- read.csv(file_name, na.strings = c("", "NA", "?df"))

# Data preprocessing
imputation_values <- readRDS(IMPUTATION_FILE)
for (column in names(df)[sapply(df, function(col) any(is.na(col)))]) {
  df[, column][is.na(df[, column])] <- imputation_values[[column]]
}

# Saving the id column in a different variable and then dropping it.
ids <- df[[id_feature]]
df[[id_feature]] <- NULL

# Encoding
if (length(categorical_features) > 0 && file.exists(OHE_ENCODER_FILE)) {
  encoder <- readRDS(OHE_ENCODER_FILE)
  test_df_encoded <- dummy_cols(df, select_columns = categorical_features, remove_selected_columns = TRUE)
  encoded_columns <- readRDS(OHE_ENCODER_FILE)
  # Add missing columns with 0s
    for (col in encoded_columns) {
        if (!col %in% colnames(test_df_encoded)) {
            test_df_encoded[[col]] <- 0
        }
    }

# Remove extra columns
    extra_cols <- setdiff(colnames(test_df_encoded), c(colnames(df), encoded_columns))
    df <- test_df_encoded[, !names(test_df_encoded) %in% extra_cols]
}

type <- ifelse(model_category == "binary_classification", "response", "probs")

# Making predictions
model <- readRDS(PREDICTOR_FILE_PATH)
predictions <- predict(model, newdata = df, type = type)

# Getting the original labels
encoder <- readRDS(LABEL_ENCODER_FILE)
target <- readRDS(ENCODED_TARGET_FILE)
class_names <- encoder[target + 1]
unique_classes <- unique(class_names)
unique_classes <- sort(unique_classes)

if (model_category == 'binary_classification'){
    Prediction1 <- predictions
    Prediction2 <- 1 - Prediction1
    predictions_df <- data.frame(Prediction1 = Prediction1, Prediction2 = Prediction2)
} else{
    predictions_df <- predictions
}
colnames(predictions_df) <- unique_classes
predictions_df <- tibble(ids = ids) %>% bind_cols(predictions_df)
colnames(predictions_df)[1] <- id_feature

write.csv(predictions_df, PREDICTIONS_FILE, row.names = FALSE)