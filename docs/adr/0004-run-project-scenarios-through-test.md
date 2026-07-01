# Run Project Scenarios Through Test

Flutter Pilot will extend `test` so no-argument runs discover Project Scenarios
from the default `pilot/` directory, and directory arguments discover Project
Scenarios from that directory. Directory discovery runs only YAML files with
top-level `scenario:` metadata, leaving metadata-free YAML files available as
Step Libraries. A Project Run launches the Target App Package once, runs the
first Scenario directly, hot restarts before later Scenarios, keeps each
Scenario Run in its own child run directory, and writes a batch-level
`project_run_report.json`.

This keeps `test` as the single Scenario execution command while giving CI and
local users a full-project verification path. The trade-off is that Project
Runs become a distinct artifact shape and depend on Flutter hot restart for
state reset, but they avoid the cost of cold-launching the app for every
Scenario and avoid mis-running shared Step Library YAML files.
