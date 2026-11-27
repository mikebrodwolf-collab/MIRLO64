# Emit detailed post-fit setup paths for the failing CPU clock.
# Run from the repository root after tools/nightly.sh has completed its fit.
project_open -revision mirlo projects_a2_nightly/mirlo
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path -show_routing -file projects_a2_nightly/output_files/mirlo.timing_paths.rpt
delete_timing_netlist
project_close
