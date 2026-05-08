# ---------------------------------------------------------------------------
# run_sim.tcl — open a kernel test-stand Vivado project and run its
# behavioural testbench in xsim batch mode.  The simulator runs to
# completion (the testbench calls $finish at the end of the test matrix);
# results are written to <data_dir>/<kernel>_test_report.json by the
# testbench's scoreboard.
#
# Invoked by scripts/run_tb.sh as:
#   vivado -mode batch -source run_sim.tcl \
#       -tclargs <xpr> <tb> <data_dir> <report> <ip_repo>
#
# tclargs:
#   xpr        absolute path to the .xpr project file
#   tb         simulation top-level module (e.g. conv_tb)
#   data_dir   absolute directory containing manifest.txt + test_*.hex fixtures
#   report     absolute path for the JSON report the scoreboard writes
#   ip_repo    optional IP repository path; empty string leaves the project's
#              stored ip_repo_paths untouched.  Either way ts_prepare_bd will
#              still upgrade any locked kernel IPs before simulation.
# ---------------------------------------------------------------------------

if {[llength $argv] < 5} {
    puts stderr "run_sim.tcl: expected 5 tclargs (xpr tb data_dir report ip_repo), got [llength $argv]"
    exit 1
}

set xpr      [lindex $argv 0]
set tb       [lindex $argv 1]
set data_dir [lindex $argv 2]
set report   [lindex $argv 3]
set ip_repo  [lindex $argv 4]

source [file join [file dirname [info script]] lib.tcl]

puts "\[run_sim\] Opening $xpr"
open_project $xpr

ts_apply_ip_repo $ip_repo

# The simulation top usually lives in the sim_1 fileset, but ts_prepare_bd
# rewires the synthesis top in [current_fileset].  Pass an empty wrapper-top
# so the proc only handles IP upgrades + BD-target/wrapper regen.
ts_prepare_bd ""

set sim_set [get_filesets sim_1]
puts "\[run_sim\] Setting sim top to $tb"
set_property top $tb $sim_set

# Pass the data dir + report path to the testbench via plusargs.  The
# testbench reads $value$plusargs("DATA_DIR=%s", ...) and ("REPORT=%s", ...).
# We intentionally do NOT escape the values further — Vivado handles
# quoting of -testplusarg internally for xsim.
set_property -name {xsim.simulate.xsim.more_options} \
    -value "-testplusarg DATA_DIR=$data_dir -testplusarg REPORT=$report" \
    -objects $sim_set

# Kill the GUI launch even if some property in the project requested it.
set_property -name {xsim.simulate.runtime} -value {0us} -objects $sim_set

puts "\[run_sim\] launch_simulation"
launch_simulation -mode behavioral -simset $sim_set

puts "\[run_sim\] run -all"
run -all

puts "\[run_sim\] DONE  report=$report"
close_sim
close_project
