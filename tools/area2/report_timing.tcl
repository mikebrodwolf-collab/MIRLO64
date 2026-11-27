# Emit detailed post-fit setup paths for the failing CPU clock.
# Quartus changes into the project directory after project_open.
project_open -revision mirlo projects_a2_nightly/mirlo
create_timing_netlist
read_sdc
update_timing_netlist
set report_file [file normalize "output_files/mirlo.timing_paths.rpt"]
report_timing -setup -npaths 20 -detail full_path -show_routing -file $report_file
delete_timing_netlist
project_close
