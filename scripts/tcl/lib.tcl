# ---------------------------------------------------------------------------
# lib.tcl — shared Tcl helpers for the cormorant_test_stand build/sim scripts.
#
# Sourced by:  build_hw.tcl, run_sim.tcl
#
# Both helpers must run AFTER open_project — they operate on [current_project]
# and the source filesets attached to it.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ts_apply_ip_repo — override the project's IP repository path and rebuild
# the catalog so newly-rebuilt kernel IPs are picked up.
#
# Pass an empty string to leave the path stored in the .xpr untouched.  The
# Vivado open_project still re-stats the existing path and locks IPs whose
# version differs, but this proc forces a full rescan when the caller wants
# to swap repos at run time (e.g. CI pointing at a different artefact dir).
# ---------------------------------------------------------------------------
proc ts_apply_ip_repo {ip_repo} {
    if {$ip_repo eq ""} {
        return
    }
    set ip_repo [file normalize $ip_repo]
    if {![file isdirectory $ip_repo]} {
        error "ts_apply_ip_repo: -ip-repo directory not found: $ip_repo"
    }
    puts "\[ts\] Setting IP repository: $ip_repo"
    set_property ip_repo_paths [list $ip_repo] [current_project]
    update_ip_catalog -rebuild
    puts "\[ts\] IP catalog updated"
}

# ---------------------------------------------------------------------------
# ts_prepare_bd — make sure the block design's HDL targets and wrapper are
# in sync with the IP catalog before synth/sim runs.  This is the place
# where stale kernel IPs are detected and upgraded.
#
#   1. Any IP whose stored XCI is older than the catalog is reported as
#      LOCKED — running upgrade_ip rebuilds the XCI from the new source.
#   2. generate_target rebuilds the BD's HDL output (.gen/<bd>/...).  Safe
#      to run on an already-up-to-date tree (it's a no-op then).
#   3. make_wrapper rewrites design_<k>_wrapper.v at the project's current
#      path.  Required on a clean checkout where *.gen/ is absent and the
#      fileset's stored wrapper path is stale.
#
# The caller passes the wrapper-top module name from the registry so we can
# also (re)set [current_fileset] top — keeps `set_property top` consistent
# whatever the .xpr last saved.
# ---------------------------------------------------------------------------
proc ts_prepare_bd {wrapper_top} {
    set locked [get_ips -quiet -filter {IS_LOCKED == 1}]
    if {[llength $locked] > 0} {
        set names {}
        foreach ip $locked { lappend names [get_property NAME $ip] }
        puts "\[ts\] Upgrading [llength $locked] locked IP(s): [join $names {, }]"
        upgrade_ip $locked
        puts "\[ts\] IP upgrade complete"
    } else {
        puts "\[ts\] No locked IPs"
    }

    set bd_files [get_files -of_objects [get_filesets sources_1] \
                      -filter {FILE_TYPE == "Block Designs"}]
    if {[llength $bd_files] == 0} {
        puts "\[ts\] No block design in sources_1 — skipping BD wrapper regen"
        return
    }
    set bd_file [lindex $bd_files 0]
    puts "\[ts\] Generating BD targets: [file tail $bd_file]"
    generate_target all $bd_file

    puts "\[ts\] Creating BD wrapper"
    set wrapper [make_wrapper -files $bd_file -top]
    if {[llength [get_files -quiet $wrapper]] == 0} {
        add_files -norecurse $wrapper
        puts "\[ts\] Wrapper added: [file tail $wrapper]"
    } else {
        puts "\[ts\] Wrapper already registered at current path"
    }

    if {$wrapper_top ne ""} {
        set_property top $wrapper_top [current_fileset]
    }
    update_compile_order -fileset sources_1
    puts "\[ts\] BD preparation complete"
}
