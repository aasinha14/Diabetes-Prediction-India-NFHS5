# Diabetes Prediction in India: Lessons Learnt from NFHS-5

Can easy-to-collect indicators (age, BMI, blood pressure, hypertension, wealth, residence, lifestyle) identify who is on diabetes medicine in India, and where do screening and treatment gaps lie?

This project uses the biomarker module of the National Family Health Survey 2019-21 (NFHS-5): **770,295 adults aged 15-49** after cleaning. Course project, MA Public Policy & Governance, TISS Hyderabad (Decision Modelling).

## Key findings
- **Model:** a pruned decision tree (depth 6, 45 leaves) predicts diabetes-medicine use with **test AUC 0.80** (5-fold CV AUC 0.81; unpruned tree: 0.58, i.e. overfit). Without glucose, AUC is 0.75.
- **Screening gap:** for every person on diabetes medicine, about **five more** have random glucose above 140 mg/dL and are not on medicine.
- **Risk gradients (unweighted, % on medicine):** 0.47% at ages 15-19 vs 3.40% at 45-49; obese 3.96% vs underweight 0.55%; hypertensive 5.10% vs 0.90%; richest wealth quintile 1.94% vs poorest 0.61%.
- **Treatment gap by wealth:** among people with glucose above 200 mg/dL, those in the poorest households are on medicine far less often (18%) than richer people (26-46%).
- **Not supported:** alcohol, tobacco and education show no meaningful difference. Family history is not recorded in NFHS-5, so the genetics hypothesis cannot be tested.

## Method in brief
1. **Data build (Stata):** women's (IR), men's (MR) and household (HR) files combined; men's BMI taken from HR and matched on cluster, household and line number; NFHS special codes (994-998, 9998) converted to missing; BMI and wealth score rescaled; BP averaged over readings 2-3.
2. **Outcome:** *currently taking medicine to lower blood glucose* (`sb57` / `smb57`). A glucose cut-off was deliberately **not** used, because glucose is also a predictor and the model would simply learn the definition (data leakage).
3. **Missing values:** listwise deletion (5.6% of rows); deleted rows compared with kept rows to check for bias.
4. **Outliers:** implausible readings deleted; BP and BMI capped at +/-3 sigma; glucose left uncapped because its extreme values are largely the diabetics being predicted. 1.5xIQR also compared.
5. **Model:** 70/30 stratified split; decision trees (unpruned baseline, tuned with balanced class weights and 5-fold cross-validation, and a no-glucose version); judged on sensitivity, specificity and AUC rather than accuracy, since only 1.2% are positive.
6. **Validation:** train vs test, fold stability, ROC curves, threshold trade-offs, and checks against self-reported diabetes and doctor-told high glucose.
7. **Inference:** group comparisons and chi-square tests for each hypothesis.

## Repository structure
```
stata/nfhs5_build_all.do              # IR + MR + HR -> one clean CSV (edit the paths at the top)
notebooks/01_cleaning_descriptives.ipynb   # missing values, outliers, descriptive statistics
notebooks/02_model_validation.ipynb        # decision trees, cross-validation, hypothesis tests
report/                                # final report (PDF)
```

## Data access (not included)
NFHS-5 microdata cannot be redistributed. Register and request **India NFHS-5 (2019-21) Individual (IR), Men's (MR) and Household (HR)** recode files at <https://dhsprogram.com/data/>. Place them in the folder structure described in the do-file, run `nfhs5_build_all.do` to produce `nfhs5_diabetes_clean.csv`, then run the two notebooks in order (written for Google Colab with the CSV in a Drive folder `NFHS5_project`; they also run locally).

## Limitations
The outcome covers only *diagnosed and treated* diabetes; glucose is a single random (non-fasting) reading; the data are cross-sectional (associations, not causation); the sample is limited to ages 15-49; figures are unweighted, so they describe the surveyed sample rather than national estimates.

## Methods and AI use
I chose the research question and indicators, ran the pipeline on the NFHS-5 files (Stata and Google Colab), and reviewed and interpreted the outputs. The codes were developed with AI assistance (Claude, Anthropic).
