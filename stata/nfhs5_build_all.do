/*==========================================================================
  NFHS-5 DIABETES PREDICTION PROJECT - ONE-STEP BUILD
  -------------------------------------------------------------------------
  Input : IR (women), MR (men), HR (household) .dta files of NFHS-5 India
  Output: nfhs5_diabetes_clean.csv  (+ .dta copy and a .log file)
          825,954 rows (women 15-49 + men 15-54), one row per person

  What this file does, in order:
    PART 1  Men's BMI: taken from HR (stored one column per household member),
            reshaped to one row per man
    PART 2  Men (MR): needed columns + BMI attached (merge), renamed to the
            women's variable names
    PART 3  Women (IR): needed columns, then men appended below them
    PART 4  Optional diagnostics: special codes and blank-value checks
    PART 5  Cleaning: special codes -> missing, units fixed, variables built
    PART 6  Labels, automatic checks, summary tables, export

  Missing values and outliers are NOT treated here on purpose: that is done
  in the Python notebook (report sections 1 and 2).

  Runtime: about 1-3 minutes. Only the SETTINGS block needs editing.
==========================================================================*/

version 14
clear all
set more off
set linesize 200


/*--------------------------------------------------------------------------
  SETTINGS  (edit here only)
--------------------------------------------------------------------------*/
cd "PATH/TO/YOUR/NFHS-5/FOLDER"   // <- edit: folder holding the IR, MR and HR folders

local IR "IR File (Women with completed interviews)\IAIR7EFL.DTA"
local MR "MR File (Men with completed interview)\IAMR7EFL.DTA"
local HR "HR File (Household)\IAHR7EFL.DTA"

local out_name         "nfhs5_diabetes_clean"
local show_diagnostics 1     // 1 = print special-code and blank-value checks
local restrict_age49   0     // 1 = keep ages 15-49 only (the Python notebook does this anyway)


capture log close
log using "`out_name'_build.log", text replace
display "Started: " c(current_date) " " c(current_time)

* Stop early with a clear message if a file path is wrong
foreach f in IR MR HR {
    capture confirm file "``f''"
    if _rc {
        display as error "File not found: ``f''   -> fix the path in SETTINGS"
        log close
        exit 601
    }
}


/*--------------------------------------------------------------------------
  PART 1: MEN'S BMI FROM THE HOUSEHOLD (HR) FILE
  HR stores men's measurements side by side: hb40_01 ... hb40_20 = BMI of
  man 1 ... man 20 in the household; hb0_xx = his line number in the roster.
--------------------------------------------------------------------------*/
display _newline "===== PART 1: men's BMI from HR ====="

use "`HR'" in 1/1, clear
capture confirm variable hb0_01 hb40_01
if _rc {
    display as error "Men's line number (hb0_01) or BMI (hb40_01) not found in HR."
    lookfor "body mass" index
    log close
    exit 111
}
local hasage 0
capture confirm variable hb1_01
if !_rc local hasage 1

local agevars ""
local stubs   "hb0_ hb40_"
if `hasage' {
    local agevars "hb1_*"
    local stubs   "hb0_ hb1_ hb40_"
}

use hv001 hv002 hb0_* `agevars' hb40_* using "`HR'", clear

* keep only households where at least one man was listed
egen byte n_men = rownonmiss(hb0_*)
drop if n_men == 0
drop n_men

* wide (one column per man) -> long (one row per man)
reshape long `stubs', i(hv001 hv002) j(idx) string
drop if missing(hb0_)
rename (hv001 hv002 hb0_ hb40_) (mv001 mv002 mv003 bmi_raw)
if `hasage' rename hb1_ hb_age

duplicates report mv001 mv002 mv003
duplicates drop mv001 mv002 mv003, force
drop idx

tempfile menbmi
save `menbmi'


/*--------------------------------------------------------------------------
  PART 2: MEN (MR) - needed columns, attach BMI, rename to women's names
--------------------------------------------------------------------------*/
display _newline "===== PART 2: men (MR) ====="

use mcaseid mv001 mv002 mv003 mv005 mv024 smdist mv012 mv025 mv106 mv133 ///
    mv190 mv191 smb18s smb18d smb25s smb25d smb29s smb29d smb74 smb53     ///
    smb20 smb21 sm619 mv463z smb56 smb57 sm627a using "`MR'", clear

* MERGE = add columns to the same people (matched on cluster + household + line)
merge 1:1 mv001 mv002 mv003 using `menbmi', keep(master match)
display "Men matched to their BMI (3 = matched, 1 = not found in HR):"
tab _merge

if `hasage' {
    quietly count if _merge == 3
    local n_match = r(N)
    quietly count if _merge == 3 & hb_age != mv012
    display "Sanity check - age differs between HR and MR for " r(N) ///
            " of " `n_match' " matched men (should be well under 1%)"
    drop hb_age
}
drop _merge

* tobacco for men: mv463z ("smokes nothing") already counts bidis
gen byte tobacco = (mv463z == 0) if !missing(mv463z)

* rename to the women's (IR) names so the cleaning code runs once for both
rename mcaseid caseid
rename mv* v*
rename smb* sb*
rename sm619  s720
rename sm627a s728a
rename smdist sdist
rename bmi_raw v445
drop v463z
gen byte female = 0

tempfile men
save `men'


/*--------------------------------------------------------------------------
  PART 3: WOMEN (IR), THEN APPEND MEN BELOW THEM
--------------------------------------------------------------------------*/
display _newline "===== PART 3: women (IR) + append men ====="

use caseid v001 v002 v003 v005 v024 sdist v012 v025 v106 v133 v190 v191 ///
    v445 sb18s sb18d sb25s sb25d sb29s sb29d sb74 sb53 sb20 sb21 s720  ///
    v463z s708 sb56 sb57 s728a using "`IR'", clear

* tobacco for women: v463z misses some bidi smokers, so add s708
* (s708: 1 = every day, 2 = some days, 3 = not at all)
gen byte tobacco = (v463z == 0 | inlist(s708, 1, 2))
drop v463z s708
gen byte female = 1

* APPEND = stack rows (same columns, different people)
append using `men'
display "Rows after append (0 = men, 1 = women):"
tab female


/*--------------------------------------------------------------------------
  PART 4: OPTIONAL DIAGNOSTICS (useful numbers for the report)
--------------------------------------------------------------------------*/
if `show_diagnostics' {
    display _newline "===== PART 4: diagnostics ====="

    display _newline "Special codes found (994 refused, 995 technical, 996 other, 998 not tested):"
    foreach v in sb18s sb18d sb25s sb25d sb29s sb29d sb74 {
        quietly count if `v' >= 994 & !missing(`v')
        display "  `v': " %9.0fc r(N)
    }
    quietly count if v445 >= 9990 & !missing(v445)
    display "  v445 (BMI, 9998 = flagged): " %9.0fc r(N)

    display _newline "What do blanks in the target mean? Told high glucose (sb56) vs on medicine (sb57):"
    tab sb56 sb57, missing
    display "-> sb57 is blank only where sb56 is blank (not in the biomarker module), so blanks stay missing."

    display _newline "Women's tobacco: 'uses no tobacco' column vs bidi question is handled above."
}


/*--------------------------------------------------------------------------
  PART 5: CLEANING AND BUILDING THE ANALYSIS VARIABLES
--------------------------------------------------------------------------*/
display _newline "===== PART 5: cleaning ====="

* special codes -> missing
foreach v in sb18s sb18d sb25s sb25d sb29s sb29d sb74 {
    replace `v' = . if `v' >= 994
}
replace v445 = . if v445 >= 9990

* --- predictors ---
gen double glucose        = sb74
gen double hrs_since_meal = sb53

* BP: mean of 2nd and 3rd readings (1st is often high); 1st used only if both missing
egen double bp_sys = rowmean(sb25s sb29s)
egen double bp_dia = rowmean(sb25d sb29d)
replace bp_sys = sb18s if missing(bp_sys)
replace bp_dia = sb18d if missing(bp_dia)

gen double bmi = v445 / 100                       // stored x100

* hypertension (diagnosed): told high BP by a health professional OR on BP medicine
gen byte hypertension = (sb20 == 1 | sb21 == 1) if !missing(sb20) | !missing(sb21)

gen byte   alcohol         = s720
gen byte   age             = v012
gen byte   edu_years       = v133
gen byte   edu_level       = v106                 // 0 none, 1 primary, 2 secondary, 3 higher
gen byte   urban           = (v025 == 1)
gen byte   wealth_quintile = v190                 // 1 poorest ... 5 richest
gen double wealth_score    = v191 / 100000        // 5 implied decimals

* --- outcomes ---
gen byte diab_med  = sb57                         // TARGET: on medicine to lower blood glucose
gen byte diab_told = sb56                         // told high glucose by a health professional
gen byte diab_self = s728a if s728a < 8           // self-reported diabetes (8 = don't know)

* glucose >140 OR on medicine - for comparison only (never with glucose as a predictor)
gen byte diab_composite = .
replace diab_composite = 0 if !missing(glucose) & !missing(diab_med)
replace diab_composite = 1 if (glucose > 140 & !missing(glucose)) | diab_med == 1

* --- identifiers and survey design ---
gen str17 person_id = cond(female == 1, "W", "M") + strtrim(caseid)
decode v024, gen(state_name)
rename (v024 sdist v001) (state district cluster)
gen double wt = v005 / 1000000

if `restrict_age49' {
    drop if age > 49
    display "Restricted to ages 15-49."
}


/*--------------------------------------------------------------------------
  PART 6: KEEP, LABEL, CHECK, EXPORT
--------------------------------------------------------------------------*/
display _newline "===== PART 6: final file ====="

keep  person_id female age edu_years edu_level urban wealth_quintile wealth_score ///
      glucose hrs_since_meal bp_sys bp_dia bmi hypertension alcohol tobacco      ///
      diab_med diab_told diab_self diab_composite state state_name district cluster wt
order person_id female age edu_years edu_level urban wealth_quintile wealth_score ///
      glucose hrs_since_meal bp_sys bp_dia bmi hypertension alcohol tobacco      ///
      diab_med diab_told diab_self diab_composite state state_name district cluster wt

label var person_id      "W/M + NFHS case id"
label var female         "1 = woman, 0 = man"
label var age            "age in years"
label var edu_years      "years of education"
label var edu_level      "education level"
label var urban          "1 = urban, 0 = rural"
label var wealth_quintile "wealth quintile"
label var wealth_score   "wealth index factor score"
label var glucose        "random blood glucose (mg/dL)"
label var hrs_since_meal "hours since last ate before glucose test"
label var bp_sys         "systolic BP, mean of readings 2-3 (mm Hg)"
label var bp_dia         "diastolic BP, mean of readings 2-3 (mm Hg)"
label var bmi            "body mass index (kg/m2)"
label var hypertension   "told high BP or on BP medicine"
label var alcohol        "drinks alcohol"
label var tobacco        "uses any tobacco (incl. bidis)"
label var diab_med       "TARGET: on medicine to lower blood glucose"
label var diab_told      "told high blood glucose by health professional"
label var diab_self      "self-reported current diabetes"
label var diab_composite "glucose >140 or on medicine (comparison only)"
label var wt             "sample weight (women's/men's, de-normalised)"

label define yesno   0 "No" 1 "Yes", replace
label define sexlbl  0 "Man" 1 "Woman", replace
label define reslbl  0 "Rural" 1 "Urban", replace
label define edulbl  0 "None" 1 "Primary" 2 "Secondary" 3 "Higher", replace
label define wqlbl   1 "Poorest" 2 "Poorer" 3 "Middle" 4 "Richer" 5 "Richest", replace
label values hypertension alcohol tobacco diab_med diab_told diab_self diab_composite yesno
label values female sexlbl
label values urban reslbl
label values edu_level edulbl
label values wealth_quintile wqlbl

* --- automatic checks: the do-file stops with an error if any fails ---
display _newline "Automatic checks:"
isid person_id                                      // every person appears once
assert glucose < 994 if !missing(glucose)           // no glucose codes left
assert bp_sys  < 994 if !missing(bp_sys)            // no BP codes left
assert bmi     < 99  if !missing(bmi)               // no BMI codes left
assert inlist(female, 0, 1)
display "  All checks passed."

* --- summary for the report ---
display _newline "Final file:"
count
codebook, compact

display _newline "Missing values per variable:"
misstable summarize

display _newline "Target by gender (column %):"
tab diab_med female, col

display _newline "Complete cases on predictors + target (what dropna() will keep):"
count if !missing(glucose, bp_sys, bp_dia, bmi, hypertension, alcohol, tobacco, ///
                  age, edu_years, urban, wealth_score, diab_med)

* --- save ---
compress
save "`out_name'.dta", replace
export delimited using "`out_name'.csv", nolabel replace

display _newline "Finished: " c(current_date) " " c(current_time)
display "Saved `out_name'.csv and `out_name'.dta"
log close
