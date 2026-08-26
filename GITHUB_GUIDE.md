# GitHub Upload — Complete Beginner Walkthrough

No command line. No git commands. Just your web browser.

---

# PART 1 — What changed, in plain terms

## Your old setup

You had **two files**:

| File | What it was |
|---|---|
| `Exhibit_2_31_R_Source_Code_Final.R` | One long R script that invented its own data |
| `Exhibit_2_31_DSS_Final__2_.html` | One giant HTML file with the map data baked inside it |

**The problem:** the map wasn't showing Wisconsin census tracts. It was showing
rectangles. Your R script had only four numbers per county (the corners of a box),
and it chopped each box into a grid of smaller boxes. Those squares in your
screenshot were those grid cells. The tract ID numbers like `55025000100` were
invented too — they look exactly like real Census IDs, but they weren't.

That's why no amount of restyling would fix the appearance. There were no real
boundaries in the file to draw.

## Your new setup

**Nine files**, each with one job:

| File | What it does | New or changed? |
|---|---|---|
| `R/01_fetch_real_data.R` | Downloads real data from Census, CMS, and CDC | **Brand new** |
| `R/02_model.R` | Your model, rewired to use the real data | Rewritten from your script |
| `index.html` | Your dashboard, with the fake map data removed | Your file, patched |
| `README.md` | Front page people see on GitHub | **Brand new** |
| `SETUP.md` | Install and run instructions | **Brand new** |
| `docs/METHODOLOGY.md` | How the index and model work | **Brand new** |
| `docs/DATA_SOURCES.md` | Where every number comes from | **Brand new** |
| `LICENSE` | Open-source permission (MIT) | **Brand new** |
| `.gitignore` | Housekeeping file | **Brand new** |

## The three real changes

**1. Real geography replaces invented rectangles.**
Your old script built boxes from county corners. The new `01_fetch_real_data.R`
downloads actual Census Bureau tract shapes. Your map will show real Wisconsin
neighborhoods with real irregular borders.

**2. Real numbers replace calibrated guesses.**
Your old script generated population, income, and poverty figures from statistical
distributions. The new script downloads the actual figures from the American
Community Survey, CMS, and CDC.

**3. The dashboard now says what its data is.**
There's a new blue bar under the title stating which numbers are measured and which
are projected. Your old file had that caveat buried in a code comment where no
reviewer would see it.

## Also worth knowing

Your old HTML had the map data glued inside it — 471,000 characters of it. The new
version loads the map data from a separate file. This makes `index.html` 30% smaller
and lets anyone inspect your data independently, which looks better to a technical
reviewer.

---

# PART 2 — Run the R scripts first

**Do this before uploading.** The scripts create the real data files.

## Step 1 — Get a free Census key

Go to **https://api.census.gov/data/key_signup.html**

Fill in your name, email, and organization (Medical College of Wisconsin). The key
arrives by email in under a minute. It's a long string of letters and numbers.

## Step 2 — Install the R packages

Open RStudio. Paste this into the console and press Enter. It takes a few minutes.

```r
install.packages(c(
  "tidyverse","tidycensus","tigris","sf","httr","jsonlite",
  "tidymodels","ranger","xgboost","stacks","openxlsx","patchwork","scales"
))
```

## Step 3 — Save your key

Paste this, replacing `PASTE_YOUR_KEY_HERE` with the key from your email:

```r
tidycensus::census_api_key("PASTE_YOUR_KEY_HERE", install = TRUE)
```

Then **close and reopen RStudio**. This matters — the key isn't active until you do.

## Step 4 — Unzip the folder

Unzip `ltc-dss.zip` somewhere you'll find it. Your Desktop is fine.

## Step 5 — Run both scripts

In RStudio, go to **Session → Set Working Directory → Choose Directory**, and pick
the `ltc-dss` folder you just unzipped.

Then run these one at a time:

```r
source("R/01_fetch_real_data.R")
```

Wait for it to finish (3–8 minutes). It prints its progress. Then:

```r
source("R/02_model.R")
```

Wait again (2–5 minutes).

## Step 6 — Check it worked

Look inside the `data` folder. You should now see three new files:

- `wi_tracts.geojson`
- `tract_features.rds`
- `dss_payload.json`

**If those three files exist, you're ready to upload.**

If something failed, see the troubleshooting table at the end of this guide.

---

# PART 3 — Upload to GitHub

## Step 1 — Make an account

Go to **https://github.com** and click **Sign up**.

Pick a username you'd be comfortable putting in an immigration petition. Your name
is the safest choice — something like `godwin-okoduwa`.

Verify your email when GitHub sends the link.

## Step 2 — Create a repository

A "repository" is just a project folder that lives on GitHub.

1. Click the **`+`** in the top right corner
2. Click **New repository**
3. Fill it in:

| Field | What to enter |
|---|---|
| Repository name | `ltc-access-dss` |
| Description | `AI-enabled long-term care access forecasting at census-tract level` |
| Public or Private | **Public** — must be public so USCIS can view it |
| Add a README file | **Leave unchecked** |
| .gitignore | **None** |
| License | **None** |

4. Click **Create repository**

Leave those three boxes unchecked — you already have those files, and checking them
creates duplicates.

## Step 3 — Upload your files

You'll land on a mostly-empty page. Look for the link that says
**"uploading an existing file"** and click it.

Now open your `ltc-dss` folder on your computer.

**Select everything inside it** — click the first item, hold Shift, click the last —
and **drag it all onto the GitHub page**.

Make sure you're dragging the *contents* of `ltc-dss`, not the `ltc-dss` folder
itself. GitHub will keep the `R`, `data`, and `docs` subfolders organized correctly.

Wait for the upload bar to finish. The `index.html` file is about 1 MB and the data
files may be a few MB, so give it a minute.

## Step 4 — Save the upload

Scroll to the bottom. In the first box, type:

```
Initial upload: LTC access decision-support system with real federal data
```

Click the green **Commit changes** button.

**Your files are now on GitHub.** You should see them listed, with your README
displayed underneath.

---

# PART 4 — Make the dashboard live

Right now people can read your code. This step makes the dashboard actually
clickable in a browser.

1. In your repository, click **Settings** (top right of the repo, gear icon)
2. In the left sidebar, scroll down and click **Pages**
3. Under **Source**, click the dropdown and choose **Deploy from a branch**
4. Under **Branch**, choose **main**, and folder **`/ (root)`**
5. Click **Save**

Wait about a minute, then refresh the page. GitHub will show a green box with your
live address:

```
https://YOUR-USERNAME.github.io/ltc-access-dss
```

**Click it.** Your dashboard should load with real Wisconsin tract boundaries.

That URL is what goes in your RFE response.

---

# PART 5 — Two things to check

## Check 1 — Does the map show real shapes?

Open your live URL and click the **Neighborhood Maps** tab.

You should see Wisconsin's real, irregular tract boundaries — dense small shapes in
Milwaukee and Madison, large sprawling ones in the rural north.

**If you see squares, the data files didn't upload.** Go back to your repository,
click the `data` folder, and confirm `wi_tracts.geojson` is listed. If it's missing,
upload it again on its own.

## Check 2 — Is the blue data bar there?

Under the title you should see a light blue strip beginning with **DATA BASIS**,
explaining which numbers are observed and which are projected.

That bar matters. It's what prevents a reviewer from mistaking a projection for a
measurement.

---

# Troubleshooting

| What you see | Why | Fix |
|---|---|---|
| `Error: API key required` | Key not saved, or RStudio not restarted | Re-run the `census_api_key` line, then fully restart RStudio |
| `sf` won't install (Mac) | Missing map libraries | In Terminal: `brew install gdal proj geos` |
| `sf` won't install (Windows) | Usually works — try again | Restart RStudio, retry `install.packages("sf")` |
| CMS download fails | Their file URL moved | Download `NH_ProviderInfo.csv` from data.cms.gov into `data/`, re-run script 01 |
| Map shows squares | Data files weren't uploaded | Upload `data/wi_tracts.geojson` separately |
| Map area shows an error message | Data file missing on GitHub | Same fix as above |
| Live URL shows 404 | Pages still building | Wait 2 minutes and refresh |
| Nothing works when you double-click `index.html` | Expected — browsers block this | Only use the GitHub Pages URL, not the local file |

---

# Keeping it updated

Every time you improve something, upload the changed file. Each upload is
timestamped and publicly visible — that record of steady activity between now and
October 5 is itself evidence of an active, ongoing project.

To replace a file: open your repository, click **Add file → Upload files**, drag the
new version in, and commit. GitHub handles the rest.

---

# What to give your attorney

Once it's live, send them:

1. **The live dashboard URL** — `https://YOUR-USERNAME.github.io/ltc-access-dss`
2. **The code repository URL** — `https://github.com/YOUR-USERNAME/ltc-access-dss`
3. **A screenshot** of the dashboard showing real tract boundaries
4. **A note** that the system now runs on real federal data (Census ACS, CMS, CDC),
   replacing the earlier synthetic-data prototype

That fourth point matters. The RFE officer discounted your prototype. Telling them
plainly that you rebuilt it on real federal data — and giving them a URL they can
click and verify themselves — directly answers what they said was missing.
