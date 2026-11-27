# Emit detailed setup paths for the CPU clock after a failed Nightly fit.
# Run from the repository root, after tools/nightly.sh has produced projects_a2_nightly.
project_open -revision mirlo projects_a2_nightly/mirlo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path -file projects_a2_nightly/output_files/mirlo.timing_paths.rpt
delete_timing_netlist
project_close
