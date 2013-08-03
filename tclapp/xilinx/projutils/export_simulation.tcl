####################################################################################################
# COPYRIGHT NOTICE
# Copyright 2001-2013 Xilinx Inc. All Rights Reserved.
# http://www.xilinx.com/support
# 
# Date Created     :  07/12/2013
# Script name      :  export_simulation.tcl
# Procedures       :  export_simulation
# Tool Version     :  Vivado 2013.3
# Description      :  Export simulation script file for compiling the design for the target simulator
#
# Command help     :  export_simulation -help
#
# Revision History :
#   07/12/2013 1.0  - Initial version (export_simulation)
#
####################################################################################################

# title: Vivado Export Simulation Tcl Script
package require Vivado 2013.1

namespace eval ::tclapp::xilinx::projutils {

  # Generate simulation file(s) for the target simulator
  namespace export export_simulation
}

namespace eval ::tclapp::xilinx::projutils {

    proc export_simulation {args} {

        # Summary:
        # Generate design filelist for the specified simulator for standalone simulation

        # Argument Usage:
        # [-of_objects <name>]: Export simulation file(s) for the specified object
        # [-relative_to <dir>]: Make all file paths relative to the specified directory
        # [-32bit]: Perform 32bit compilation
        # [-force]: Overwrite previous files
        # -dir <name>: Directory where the simulation files is saved
        # -simulator <name>: Simulator for which simulation files will be exported (<name>: ies|vcs_mx)

        # Return Value:
        # true (0) if success, false (1) otherwise

        variable a_global_sim_vars
        variable l_valid_simulator_types

        reset_global_sim_vars

        set options [split $args " "]
        # these options are must
        if {[lsearch $options {-simulator}] == -1} {
          send_msg_id Vivado-projutils-013 ERROR "Missing option '-simulator', please type 'export_simulation -help' for usage info.\n"
          return 1
        }
        if {[lsearch $options {-dir}] == -1} {
          send_msg_id Vivado-projutils-039 ERROR "Missing option '-dir', please type 'export_simulation -help' for usage info.\n"
          return 1
        }

        # process options
        for {set i 0} {$i < [llength $args]} {incr i} {
          set option [string trim [lindex $args $i]]
          switch -regexp -- $option {
            "-of_objects"               { incr i;set a_global_sim_vars(s_of_objects) [lindex $args $i] }
            "-32bit"                    { set a_global_sim_vars(b_32bit) 1 }
            "-relative_to"              { incr i;set a_global_sim_vars(s_relative_to) [lindex $args $i] }
            "-force"                    { set a_global_sim_vars(b_overwrite_sim_files_dir) 1 }
            "-simulator"                { incr i;set a_global_sim_vars(s_simulator) [lindex $args $i] }
            "-dir"                      { incr i;set a_global_sim_vars(s_sim_files_dir) [lindex $args $i] }
            default {
              # is incorrect switch specified?
              if { [regexp {^-} $option] } {
                send_msg_id Vivado-projutils-014 ERROR "Unknown option '$option', please type 'export_simulation -help' for usage info.\n"
                return 1
              }
            }
          }
        }

        # is project open?
        set a_global_sim_vars(s_project_name) [get_property name [current_project]]
        set a_global_sim_vars(s_project_dir) [get_property directory [current_project]]

        # is valid simulator specified?
        if { [lsearch -exact $l_valid_simulator_types $a_global_sim_vars(s_simulator)] == -1 } {
          send_msg_id Vivado-projutils-015 ERROR \
            "Invalid simulator type specified. Please type 'export_simulation -help' for usage info.\n"
          return 1
        }

        # is valid relative_to set?
        if { [lsearch $options {-relative_to}] != -1} {
          set relative_file_path $a_global_sim_vars(s_relative_to)
          if { ![file exists $relative_file_path] } {
            send_msg_id Vivado-projutils-037 ERROR \
              "Invalid relative path specified! Path does not exist:$a_global_sim_vars(s_relative_to)\n"
            return 1
          }
        }

        # is valid tcl obj specified?
        if { ([lsearch $options {-of_objects}] != -1) && ([llength $a_global_sim_vars(s_of_objects)] == 0) } {
          send_msg_id Vivado-projutils-038 ERROR "Invalid object specified. The object does not exist.\n"
          return 1
        }
 
        # set pretty name
        if { [set_simulator_name] } {
          return 1
        }

        # is managed project?
        set a_global_sim_vars(b_is_managed) [get_property managed_ip [current_project]]

        # setup run dir
        if { [create_sim_files_dir] } {
          return 1
        }
  
        # set default object if not specified, bail out if no object found
        if { [set_default_source_object] } {
          return 1
        }

        # write script
        if { [write_sim_script] } {
          return 1
        }
      
        # TCL_OK
        return 0
    }
}

namespace eval ::tclapp::xilinx::projutils {

    #
    # export_simulation tcl script argument & file handle vars
    #
    variable a_global_sim_vars
    variable l_compile_order_files [list]

    variable l_valid_simulator_types [list]
    set l_valid_simulator_types [list ies vcs_mx]

    variable l_valid_ip_extns [list]
    set l_valid_ip_extns [list ".xci" ".bd" ".slx"]

    variable s_data_files_filter
    set s_data_files_filter "FILE_TYPE == \"Data Files\" || FILE_TYPE == \"Memory Initialization Files\" || FILE_TYPE == \"Coefficient Files\""

    proc reset_global_sim_vars {} {

        # Summary: initializes global namespace simulation vars
        # This helper command is used to reset the simulation variables used in the script.

        # Argument Usage:
        # none

        # Return Value:
        # None

        variable a_global_sim_vars

        set a_global_sim_vars(s_simulator)               ""
        set a_global_sim_vars(s_simulator_name)          ""
        set a_global_sim_vars(s_sim_files_dir)           ""
        set a_global_sim_vars(b_32bit)                   0
        set a_global_sim_vars(s_relative_to)             ""             
        set a_global_sim_vars(b_overwrite_sim_files_dir) 0
        set a_global_sim_vars(s_driver_script)           ""
        set a_global_sim_vars(s_of_objects)              ""
        set a_global_sim_vars(s_sim_top)                 ""
        set a_global_sim_vars(s_project_name)            ""
        set a_global_sim_vars(s_project_dir)             ""
        set a_global_sim_vars(b_is_managed)              0 

        set l_compile_order_files                        [list]

    }

   proc set_default_source_object {} {

       # Summary: If -of_objects not specified, then for managed-ip project error out
       #          or set active simulation fileset for an RTL/GateLvl project

       # Argument Usage:
       # none

       # Return Value:
       # true (0) if success, false (1) otherwise

       variable a_global_sim_vars
       set tcl_obj $a_global_sim_vars(s_of_objects)
       if { [string length $tcl_obj] == 0 } {
         if { $a_global_sim_vars(b_is_managed) } {
           set ips [get_ips]
           if {[llength $ips] == 0} {
             send_msg_id Vivado-projutils-016 INFO "No IP's found in the current project.\n"
             return 1
           }
           # object not specified, error
           send_msg_id Vivado-projutils-035 ERROR "No IP source object specified. Please type 'export_simulation -help' for usage info.\n"
           return 1
         } else {
           set curr_simset [current_fileset -simset]
           set sim_files [get_files -quiet -compile_order sources -used_in simulation -of_objects [get_filesets $curr_simset]]
           if { [llength $sim_files] == 0 } {
             send_msg_id Vivado-projutils-017 INFO "No simulation files found in the current simset.\n"
             return 1
           }
           set a_global_sim_vars(s_of_objects) $curr_simset
         }
       } else {
         # is valid tcl object?
         if { ![is_ip $tcl_obj] } {
           if { [is_fileset $tcl_obj] } {
             set fs_type [get_property fileset_type [get_filesets $tcl_obj]]
             if { [string equal -nocase $fs_type "Constrs"] } {
               send_msg_id Vivado-projutils-034 ERROR "Invalid object type specified\n"
               return 1
             }
           }
         } else {
           set ip_obj_count [llength [get_files -all -quiet $tcl_obj]]
           if { $ip_obj_count == 0 } {
             send_msg_id Vivado-projutils-009 ERROR "The specified object could not be found in the project:$tcl_obj\n"
             return 1
           } elseif { $ip_obj_count > 1 } {
             send_msg_id Vivado-projutils-019 ERROR "The script expects exactly one object got $ip_obj_count\n"
             return 1
           }
         }
       }
       return 0
   }

   proc write_sim_script {} {

       # Summary: Get the compiled order for the specified source object and export files

       # Argument Usage:
       # none

       # Return Value:
       # true (0) if success, false (1) otherwise

       variable a_global_sim_vars

       set tcl_obj $a_global_sim_vars(s_of_objects)

       if { [is_ip $tcl_obj] } {
         set a_global_sim_vars(s_sim_top) [file tail [file root $tcl_obj]]
         if {[export_sim_files_for_ip $tcl_obj]} {
           return 1
         }
       } elseif { [is_fileset $tcl_obj] } {
         set a_global_sim_vars(s_sim_top) [get_property top [get_filesets $tcl_obj]]
         if {[string length $a_global_sim_vars(s_sim_top)] == 0} {
           set a_global_sim_vars(s_sim_top) "unknown"
         }
         if {[export_sim_files_for_fs $tcl_obj]} {
           return 1
         }
       } else {
         send_msg_id Vivado-projutils-020 INFO "Unsupported object source: $tcl_obj\n"
         return 1
       }

       send_msg_id Vivado-projutils-021 INFO "\nScript generated:$a_global_sim_vars(s_sim_files_dir)/$a_global_sim_vars(s_driver_script)\n"

       return 0
   }

   proc export_sim_files_for_ip { tcl_obj } {

       # Summary: 

       # Argument Usage:
       # source object

       # Return Value:
       # true (0) if success, false (1) otherwise
     
       variable a_global_sim_vars
       variable s_data_files_filter
       variable l_compile_order_files
 
       set obj_name [file root [file tail $tcl_obj]]
       set ip_filename [file tail $tcl_obj]
       set l_compile_order_files [get_files -quiet -compile_order sources -used_in simulation -of_objects [get_files -quiet *$ip_filename]]

       set simulator $a_global_sim_vars(s_simulator)
       set ip_name [file root $ip_filename]
       set a_global_sim_vars(s_driver_script) "${ip_name}_sim_${simulator}.txt"

       if {[export_simulation_for_object $obj_name]} {
         return 1
       }

       # fetch ip data files and export to output dir
       set data_files [get_files -all -quiet -of_objects [get_files -quiet *$ip_filename] -filter $s_data_files_filter]
       export_data_files $data_files

       return 0
   }

   proc export_sim_files_for_fs { tcl_obj } {

       # Summary: 

       # Argument Usage:
       # source object

       # Return Value:
       # true (0) if success, false (1) otherwise
       
       variable a_global_sim_vars
       variable l_compile_order_files
 
       set obj_name $tcl_obj
       set used_in_val "simulation"
       switch [get_property fileset_type [get_filesets $tcl_obj]] {
         "DesignSrcs"     { set used_in_val "synthesis" }
         "SimulationSrcs" { set used_in_val "simulation"}
         "BlockSrcs"      { set used_in_val "synthesis" }
       }

       set l_compile_order_files [get_files -quiet -compile_order sources -used_in $used_in_val -of_objects [get_filesets $tcl_obj]]
       if { [llength $l_compile_order_files] == 0 } {
         send_msg_id Vivado-projutils-018 INFO "Empty fileset: $obj_name\n"
         return 1
       } else {
         set simulator $a_global_sim_vars(s_simulator)
         set a_global_sim_vars(s_driver_script) "$a_global_sim_vars(s_sim_top)_sim_${simulator}.txt"
         if {[export_simulation_for_object $obj_name]} {
           return 1
         }

         # fetch data files for all IP's in simset and export to output dir
         export_fileset_ip_data_files
       }
 
       return 0
   }

   proc is_ip { obj } {

       # Summary: Determine if specified source object is IP

       # Argument Usage:
       # source object

       # Return Value:
       # true (1) if specified object is an IP, false (0) otherwise
      
       variable l_valid_ip_extns 

       if { [lsearch -exact $l_valid_ip_extns [file extension $obj]] >= 0 } {
         return 1
       }
       return 0
   }

   proc is_fileset { obj } {

       # Summary: Determine if specified source object is fileset

       # Argument Usage:
       # source object

       # Return Value:
       # true (1) if specified object is a fileset, false (0) otherwise

       if {[string equal [rdi::get_attr_specs FILESET_TYPE -object $obj] "FILESET_TYPE"]} {
         return 1
       }

       return 0
   }

   proc set_simulator_name {} {

       # Summary: Set simulator name for the specified simulator type

       # Argument Usage:
       # none

       # Return Value:
       # True (0) if name set, false (1) otherwise

       variable a_global_sim_vars
       set simulator $a_global_sim_vars(s_simulator)
       switch -regexp -- $simulator {
         "ies"       { set a_global_sim_vars(s_simulator_name) "Cadence Incisive Enterprise" }
         "vcs_mx"    { set a_global_sim_vars(s_simulator_name) "Synopsys VCS MX" }
         default {
           send_msg_id Vivado-projutils-026 ERROR "Invalid simulator ($simulator)\n"
           close $fh
           return 1
         }
       }
       return 0
   }

   proc create_sim_files_dir {} {

       # Summary: Create output directory where simulation files will be generated. Delete previous
       #          files if overwrite requested (-force)

       # Argument Usage:
       # none

       # Return Value:
       # true (0) if success, false (1) otherwise

       variable a_global_sim_vars

       if { [string length $a_global_sim_vars(s_sim_files_dir)] == 0 } {
         send_msg_id Vivado-projutils-036 ERROR "Missing directory value. Please specify the output directory path for the exported files.\n"
         return 1
       }

       set dir [file normalize [string map {\\ /} $a_global_sim_vars(s_sim_files_dir)]]
       if { ! [file exists $dir] } {
         if {[catch {file mkdir $dir} error_msg] } {
           send_msg_id Vivado-projutils-023 ERROR "failed to create the directory ($dir): $error_msg\n"
           return 1
         }
       }
       set a_global_sim_vars(s_sim_files_dir) $dir
       return 0
   }

   proc export_simulation_for_object { obj_name } {

       # Summary: Open files and write compile order for the target simulator

       # Argument Usage:
       # obj_name - source object

       # Return Value:
       # true (0) if success, false (1) otherwise

       variable a_global_sim_vars
       
       set file [file normalize [file join $a_global_sim_vars(s_sim_files_dir) $a_global_sim_vars(s_driver_script)]]

 	   # recommend -force if file exists
 	   if { [file exists $file] && (!$a_global_sim_vars(b_overwrite_sim_files_dir)) } {
         send_msg_id Vivado-projutils-032 ERROR "Simulation file '$file' already exist. Use -force option to overwrite."
 	     return 1
 	   }
         
       if { [file exists $file] } {
         if {[catch {file delete -force $file} error_msg] } {
           send_msg_id Vivado-projutils-033 ERROR "failed to delete file ($file): $error_msg\n"
           return 1
         }
       }

       set fh 0
       if {[catch {open $file w} fh]} {
         send_msg_id Vivado-projutils-025 ERROR "failed to open file to write ($file)\n"
         return 1
       }

       send_msg_id Vivado-projutils-024 INFO \
         "Generating driver script for '$a_global_sim_vars(s_simulator_name)' simulator (DESIGN OBJECT=$obj_name)...\n"

       # write header, compiler command/options
       if { [write_driver_script $fh] } {
         return 1
       }
       close $fh

       # make filelist executable
       if {[catch {exec chmod a+x $file} error_msg] } {
         send_msg_id Vivado-projutils-040 WARNING "failed to change file permissions to executable ($file): $error_msg\n"
       }

       # contains verilog sources? copy glbl to output dir
       if { [contains_verilog] } {
         if {[export_glbl_file]} {
           return 1
         }
       }

       return 0
   }

   proc write_driver_script { fh } {

       # Summary: Write driver script for the target simulator

       # Argument Usage:
       # fh   - file handle

       # Return Value:
       # true (0) if success, false (1) otherwise

       variable a_global_sim_vars

       write_script_header $fh

       # setup source dir var
       set relative_to $a_global_sim_vars(s_relative_to)
       if {[string length $relative_to] > 0 } {
         puts $fh "#"
         puts $fh "# Relative path for design sources and include directories (if any) relative to this path"
         puts $fh "#"
         puts $fh "set origin_dir \"$relative_to\""
         puts $fh ""
       }

       puts $fh "#"
       puts $fh "# STEP: compile"
       puts $fh "#"

       switch -regexp -- $a_global_sim_vars(s_simulator) {
         "ies"      { wr_driver_script_ies $fh }
         "vcs_mx"   { wr_driver_script_vcs_mx $fh }
         default {
           send_msg_id Vivado-projutils-022 ERROR "Invalid simulator ($a_global_sim_vars(s_simulator))\n"
           close $fh
           return 1
         }
       }

       # add glbl
       if { [contains_verilog] } {
         set file_str "-work work ./glbl.v"
         switch -regexp -- $a_global_sim_vars(s_simulator) {
           "ies"      { puts $fh "ncvlog $file_str" }
           "vcs_mx"   { puts $fh "vlogan $file_str" }
           default {
             send_msg_id Vivado-projutils-031 ERROR "Invalid simulator ($a_global_sim_vars(s_simulator))\n"
             close $fh
             return 1
           }
         }
       }

       puts $fh ""
       write_elaboration_cmds $fh

       puts $fh ""
       write_simulation_cmds $fh

       return 0
   }

   proc wr_driver_script_ies { fh } {

       # Summary: Write driver script for the IES simulator

       # Argument Usage:
       # file - compile order RTL file
       # fh   - file handle

       # Return Value:
       # none

       variable a_global_sim_vars
       variable l_compile_order_files

       foreach file $l_compile_order_files {
         set cmd_str [list]
         set file_type [get_property file_type [get_files -quiet -all $file]]
         set associated_library [get_property library [get_files -quiet -all $file]]
         if {[string length $a_global_sim_vars(s_relative_to)] > 0 } {
           set file "\$origin_dir/[get_relative_file_path $file $a_global_sim_vars(s_relative_to)]"
         }
         switch -regexp -nocase -- $file_type {
           "vhd" {
             set tool "ncvhdl"
             lappend cmd_str $tool
             append_compiler_options $tool $file_type cmd_str
             lappend cmd_str "-work"
             lappend cmd_str "$associated_library"
             lappend cmd_str "\"$file\""
           }
           "verilog" {
             set tool "ncvlog"
             lappend cmd_str $tool
             append_compiler_options $tool $file_type cmd_str
             lappend cmd_str "-work"
             lappend cmd_str "$associated_library"
             lappend cmd_str "\"$file\""
           }
         }
         set cmd [join $cmd_str " "]
         puts $fh $cmd
       }
   }

   proc wr_driver_script_vcs_mx { fh } {

       # Summary: Write driver script for the VCS simulator

       # Argument Usage:
       # file - compile order RTL file
       # fh   - file handle

       # Return Value:
       # none

       variable a_global_sim_vars
       variable l_compile_order_files

       foreach file $l_compile_order_files {
         set cmd_str [list]
         set file_type [get_property file_type [get_files -quiet -all $file]]
         set associated_library [get_property library [get_files -quiet -all $file]]
         if {[string length $a_global_sim_vars(s_relative_to)] > 0 } {
           set file "\$origin_dir/[get_relative_file_path $file $a_global_sim_vars(s_relative_to)]"
         }
         switch -regexp -nocase -- $file_type {
           "vhd" {
             set tool "vhdlan"
             lappend cmd_str $tool
             append_compiler_options $tool $file_type cmd_str
             lappend cmd_str "-work"
             lappend cmd_str "$associated_library"
             lappend cmd_str "$file"
           }
           "verilog" {
             set tool "vlogan"
             lappend cmd_str $tool
             append_compiler_options $tool $file_type cmd_str
             lappend cmd_str "-work"
             lappend cmd_str "$associated_library"
             lappend cmd_str "$file"
           }
         }
         set cmd [join $cmd_str " "]
         puts $fh $cmd
       }
   }

   proc write_script_header { fh } {

       # Summary: Driver script header info

       # Argument Usage:
       # fh - file descriptor

       # Return Value:
       # none

       variable a_global_sim_vars

       set curr_time   [clock format [clock seconds]]
       set version_txt [split [version] "\n"]
       set version     [lindex $version_txt 0]
       set copyright   [lindex $version_txt 2]
       set product     [lindex [split $version " "] 0]
       set version_id  [join [lrange $version 1 end] " "]

       puts $fh "#\n# $product (TM) $version_id\n#"
       puts $fh "# $a_global_sim_vars(s_driver_script): Simulation script\n#"
       puts $fh "# Generated by $product on $curr_time"
       puts $fh "# $copyright \n#"
       puts $fh "# This file contains commands for compiling the design in '$a_global_sim_vars(s_simulator_name)' simulator\n#"
       puts $fh "#*****************************************************************************************"
       puts $fh "# NOTE: To compile and run simulation, you must perform following pre-steps:-"
       puts $fh "#"
       puts $fh "# 1. Compile the Xilinx simulation libraries using the 'compile_simlib' TCL command. For more information"
       puts $fh "#    about this command, run 'compile_simlib -help' in $product Tcl Shell."
       puts $fh "#"
    
       switch -regexp -- $a_global_sim_vars(s_simulator) {
         "ies" { 
            puts $fh "# 2. Copy the CDS.lib and HDL.var files from the compiled directory location to the working directory."
            puts $fh "#    In case the libraries are compled in the working directory then ignore this step."
            puts $fh "#"
            puts $fh "# 3. Create directory for each design library* (for example: mkdir -p ius/fifo_gen)\n#"
            puts $fh "# 4. Define library mapping for each library in CDS.lib file (for example: DEFINE fifo_gen ius/fifo_gen)\n"
         }
         "vcs_mx" {
            puts $fh "# 2. Copy the synopsys_sim.setup file from the compiled directory location to the current working directory."
            puts $fh "#    In case the libraries are compled in the current working directory then ignore this step."
            puts $fh "#"
            puts $fh "# 3. Create directory for each design library* (for example: mkdir -p vcs/fifo_gen)\n#"
            puts $fh "# 4. Map libraries to physical directory location in synopsys_sim.setup file (for example: fifo_gen : vcs/fifo_gen)\n#"
         }
       }
       puts $fh "# 3. For more information please refer to the following guide:-\n#"
       puts $fh "#    Xilinx Vivado Design Suite User Guide:Logic simulation (UG900)\n#"
       puts $fh "# *Design Libraries:-\n#"
       foreach lib [get_compile_order_libs] {
         puts $fh "#  $lib"
       }
       puts $fh "#"
       puts $fh "#*****************************************************************************************\n"

   }

   proc write_elaboration_cmds { fh } {

       # Summary: Driver script header info

       # Argument Usage:
       # files - compile order files
       # fh - file descriptor

       # Return Value:
       # none

       variable a_global_sim_vars

       set tcl_obj $a_global_sim_vars(s_of_objects)
       set v_generics [list]
       if { [is_fileset $tcl_obj] } {
         set v_generics [get_property vhdl_generic [get_filesets $tcl_obj]]
       }

       puts $fh "#"
       puts $fh "# STEP: elaborate"
       puts $fh "#"

       switch -regexp -- $a_global_sim_vars(s_simulator) {
         "ies" { 
           set cmd_str [list]
           lappend cmd_str "ncelab"
           lappend cmd_str "-timescale"
           lappend cmd_str "1ns/1ps"
           foreach generic $v_generics {
             set name [lindex [split $generic "="] 0]
             set val  [lindex [split $generic "="] 1]
             if { [string length $val] > 0 } {
               lappend cmd_str "-g"
               lappend cmd_str "\"$name=>$val\""
             }
           }
           lappend cmd_str "-override_precision"
           lappend cmd_str "-lib_binding"
           lappend cmd_str "-messages"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)"
           lappend cmd_str "glbl"
           foreach library [get_compile_order_libs] {
             lappend cmd_str "-libname"
             lappend cmd_str "[string tolower $library]"
           }
           lappend cmd_str "-libname"
           lappend cmd_str "unisims_ver"
           lappend cmd_str "-libname"
           lappend cmd_str "secureip"
           if { !$a_global_sim_vars(b_32bit) } {
             lappend cmd_str "-64bit"
           }
           lappend cmd_str "-logfile"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_elab.log"
           set cmd [join $cmd_str " "]
           puts $fh $cmd
         }
         "vcs_mx" {
           set cmd_str [list]
           lappend cmd_str "vcs"
           if { !$a_global_sim_vars(b_32bit) } {
             lappend cmd_str "-full64"
           }
           lappend cmd_str "$a_global_sim_vars(s_sim_top)"
           lappend cmd_str "-l"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_comp.log"
           lappend cmd_str "-t"
           lappend cmd_str "-ps"
           lappend cmd_str "-licwait"
           lappend cmd_str "-60"
           lappend cmd_str "-o"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_simv"
           set cmd [join $cmd_str " "]
           puts $fh $cmd
         }
       }
   }

   proc write_simulation_cmds { fh } {

       # Summary: Driver script simulation commands info

       # Argument Usage:
       # files - compile order files
       # fh - file descriptor

       # Return Value:
       # none

       variable a_global_sim_vars

       puts $fh "#"
       puts $fh "# STEP: simulate"
       puts $fh "#"

       switch -regexp -- $a_global_sim_vars(s_simulator) {
         "ies" { 
           set cmd_str [list]
           lappend cmd_str "ncsim"
           if { !$a_global_sim_vars(b_32bit) } {
             lappend cmd_str "-64bit"
           }
           lappend cmd_str "-input"
           lappend cmd_str "$a_global_sim_vars(s_sim_top).do"
           lappend cmd_str "-logfile"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_sim.log"
           set cmd [join $cmd_str " "]
           puts $fh $cmd
         }
         "vcs_mx" {
           set cmd_str [list]
           lappend cmd_str "vcs"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_simv"
           lappend cmd_str "-ucli"
           lappend cmd_str "-do"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_sim.do"
           lappend cmd_str "-licwait"
           lappend cmd_str "-60"
           lappend cmd_str "-l"
           lappend cmd_str "$a_global_sim_vars(s_sim_top)_sim.log"
           set cmd [join $cmd_str " "]
           puts $fh $cmd
         }
       }
   }

   proc append_compiler_options { tool file_type opts_arg } {

       # Summary: Add switches (options) for the target compiler tool

       # Argument Usage:
       # tool - compiler name
       # file_type - file type
       # opts_arg - options list to be appended

       # Return Value:
       # none

       upvar $opts_arg opts

       variable a_global_sim_vars

       # verilog include directories
       set incl_dirs [find_verilog_incl_dirs]

       # verilog include file directories
       set incl_file_dirs [find_verilog_incl_file_dirs]

       # verilog defines
       set tcl_obj $a_global_sim_vars(s_of_objects)
       set v_defines [list]
       if { [is_fileset $tcl_obj] } {
         set v_defines [get_property verilog_define [get_filesets $tcl_obj]]
       }
       set v_generics [list]
       if { [is_fileset $tcl_obj] } {
         set v_generics [get_property vhdl_generic [get_filesets $tcl_obj]]
       }
  
       switch $tool {
         "ncvhdl" {
           lappend opts "-V93"
           lappend opts "-RELAX"
           if { !$a_global_sim_vars(b_32bit) } {
             lappend opts "-64bit"
           }
           lappend opts "-logfile"
           lappend opts "$tool.log"
           lappend opts "-append_log"
         }
         "ncvlog" {
           if { !$a_global_sim_vars(b_32bit) } {
             lappend opts "-64bit"
           }
           lappend opts "-messages"
           foreach define $v_defines {
             set name [lindex [split $define "="] 0]
             set val  [lindex [split $define "="] 1]
             if { [string length $val] > 0 } {
               lappend opts "-define"
               lappend opts "\"$name=$val\""
             }
           }
           lappend opts "-logfile"
           lappend opts "$tool.log"
           lappend opts "-append_log"
           foreach dir $incl_dirs {
             lappend opts "+incdir+\"$dir\""
           }
           foreach dir $incl_file_dirs {
             lappend opts "+incdir+\"$dir\""
           }
         }
         "vhdlan" {
           lappend opts "-93"
           if { !$a_global_sim_vars(b_32bit) } {
             lappend opts "-full64"
           }
           lappend opts "-l"
           lappend opts "$tool.log"
         }
         "vlogan" {
           if { [string equal $file_type "verilog"] } {
             lappend opts "+v2k"
           } elseif { [string equal $file_type "systemverilog"] } {
             lappend opts "-sverilog"
           }
           if { !$a_global_sim_vars(b_32bit) } {
             lappend opts "-full64"
           }
           foreach define $v_defines {
             set name [lindex [split $define "="] 0]
             set val  [lindex [split $define "="] 1]
             if { [string length $val] > 0 } {
               lappend opts "+define+"
               lappend opts "$name=$val"
             }
           }
           lappend opts "-l"
           lappend opts "$tool.log"
           foreach dir $incl_dirs {
             lappend opts "+incdir+\"$dir\""
           }
           foreach dir $incl_file_dirs {
             lappend opts "+incdir+\"$dir\""
           }
         }
       }
   }

   proc find_verilog_incl_dirs { } {

       # Summary: Get the verilog include directory paths

       # Argument Usage:
       # none

       # Return Value:
       # Sorted unique list of verilog include directories (if any)
 
       variable a_global_sim_vars

       set dir_names [list]
 
       set tcl_obj $a_global_sim_vars(s_of_objects)
       if { [is_ip $tcl_obj] } {
         set incl_dir_str [find_incl_dirs_from_ip $tcl_obj]
       } else {
         set incl_dir_str [get_property include_dirs [get_filesets $tcl_obj]]
       }

       set incl_dirs [split $incl_dir_str " "]
       foreach vh_dir $incl_dirs {
         set dir [file normalize $vh_dir]
         if {[string length $a_global_sim_vars(s_relative_to)] > 0 } {
           set dir "\$origin_dir/[get_relative_file_path $dir $a_global_sim_vars(s_relative_to)]"
         }
         lappend dir_names $dir
       }
       return [lsort -unique $dir_names]
   }

   proc find_verilog_incl_file_dirs {} {

       # Summary: Get the verilog include directory paths for files of type "Verilog Header"

       # Argument Usage:
       # none

       # Return Value:
       # Sorted unique list of verilog include directory paths for files of type "Verilog Header"

       variable a_global_sim_vars

       set dir_names [list]

       set tcl_obj $a_global_sim_vars(s_of_objects)
       if { [is_ip $tcl_obj] } {
         set vh_files [find_incl_files_from_ip $tcl_obj]
       } else {
         set filter "USED_IN_SIMULATION == 1 && FILE_TYPE == \"Verilog Header\""
         set vh_files [get_files -quiet -filter $filter]
       }

       foreach vh_file $vh_files {
         set dir [file normalize [file dirname $vh_file]]
         if {[string length $a_global_sim_vars(s_relative_to)] > 0 } {
           set dir "\$origin_dir/[get_relative_file_path $dir $a_global_sim_vars(s_relative_to)]"
         }
         lappend dir_names $dir
       }
       if {[llength $dir_names] > 0} {
         return [lsort -unique $dir_names]
       }

       return $dir_names
   }

   proc find_incl_dirs_from_ip { tcl_obj } {

       # Summary: Get the verilog include directory paths for files of type "Verilog Header" for an IP

       # Argument Usage:
       # tcl_obj - source object type

       # Return Value:
       # List of verilog include directory paths in an IP for files of type "Verilog Header"
    
       variable a_global_sim_vars 

       set ip_name [file tail $tcl_obj]
       set incl_dirs [list]
       set filter "FILE_TYPE == \"Verilog Header\""
       set vh_files [get_files -quiet -compile_order sources -used_in simulation -of_objects [get_files -quiet *$ip_name] -filter $filter]
       foreach file $vh_files {
         set dir [file dirname $file]
         if {[string length $a_global_sim_vars(s_relative_to)] > 0 } {
           set dir "\$origin_dir/[get_relative_file_path $dir $a_global_sim_vars(s_relative_to)]"
         }
         lappend incl_dirs $dir
       }
 
       return $incl_dirs
   }

   proc find_incl_files_from_ip { tcl_obj } {

       # Summary: Get the verilog include files of type "Verilog Header" for an IP

       # Argument Usage:
       # none

       # Return Value:
       # List of verilog include directory files in an IP for files of type "Verilog Header"

       variable a_global_sim_vars

       set incl_files [list]
       set ip_name [file tail $tcl_obj]
       set filter "FILE_TYPE == \"Verilog Header\""
       set vh_files [get_files -quiet -of_objects [get_files -quiet *$ip_name] -filter $filter]
       foreach file $vh_files {
         if {[string length $a_global_sim_vars(s_relative_to)] > 0 } {
           set file "\$origin_dir/[get_relative_file_path $file $a_global_sim_vars(s_relative_to)]"
         }
         lappend incl_files $file
       }
 
       return $incl_files
   }

   proc export_data_files { data_files } {

       # Summary: Copy IP data files to output directory

       # Argument Usage:
       # data_files - List of data files

       # Return Value:
       # none

       variable a_global_sim_vars
 
       set export_dir $a_global_sim_vars(s_sim_files_dir)
       
       # export now
       foreach file $data_files {
         if {[catch {file copy -force $file $export_dir} error_msg] } {
           send_msg_id Vivado-projutils-027 WARNING "failed to copy file '$file' to '$export_dir' : $error_msg\n"
         } else {
           send_msg_id Vivado-projutils-028 INFO "copied '$file'\n"
         }
       }
   }

   proc export_fileset_ip_data_files { } {

       # Summary: Copy fileset IP data files to output directory

       # Argument Usage:
       # none

       # Return Value:
       # none

       variable a_global_sim_vars
       variable s_data_files_filter
 
       set ip_filter "FILE_TYPE == \"IP\""
       set ips [get_files -all -quiet -filter $ip_filter]
       foreach ip $ips {
         set ip_name [file tail $ip]
         set data_files [get_files -all -quiet -of_objects [get_files -quiet *$ip_name] -filter $s_data_files_filter]
         export_data_files $data_files
       }

       # export fileset data files
       set fs_data_files [get_files -all -quiet -of_objects [get_filesets -quiet [current_fileset]] -filter $s_data_files_filter]
       export_data_files $fs_data_files
   }

   proc export_glbl_file {} {

       # Summary: Copies glbl.v file from install data dir to output dir

       # Argument Usage:
       # none

       # Return Value:
       # True (0) if file copied, false (1) otherwise

       variable a_global_sim_vars

       set data_dir [rdi::get_data_dir -quiet -datafile verilog/src/glbl.v]
       set file [file normalize [file join $data_dir "verilog/src/glbl.v"]]
       set export_dir $a_global_sim_vars(s_sim_files_dir)

       if {[catch {file copy -force $file $export_dir} error_msg] } {
         send_msg_id Vivado-projutils-029 WARNING "failed to copy file '$file' to '$export_dir' : $error_msg\n"
         return 1
       }

       set glbl_file [file normalize [file join $export_dir "glbl.v"]]
       send_msg_id Vivado-projutils-030 INFO "Exported glbl file (glbl.v) to output directory\n"

       return 0
   }

   proc get_compile_order_libs { } {

       # Summary: Find unique list of design libraries

       # Argument Usage:
       # files: list of design files

       # Return Value:
       # Unique list of libraries (if any)
    
       variable a_global_sim_vars
       variable l_compile_order_files

       set libs [list]
       foreach file $l_compile_order_files {
         set library [get_property library [get_files -all $file]]
         if { [lsearch -exact $libs $library] == -1 } {
           lappend libs $library
         }
       }
       return $libs
   }

   proc contains_verilog {} {

       # Summary: Check if the input file type is of type verilog or verilog header

       # Argument Usage:
       # files: list of files

       # Return Value:
       # True (1) if of type verilog, False (0) otherwise

       set filter "FILE_TYPE == \"Verilog\" || FILE_TYPE == \"Verilog Header\""
       if {[llength [get_files -quiet -all -filter $filter]] > 0} {
         return 1
       }
       return 0
   }

   proc get_relative_file_path { file_path_to_convert relative_to } {

       # Summary: Get the relative path wrt to path specified

       # Argument Usage:
       # file_path_to_convert: input file to make relative to specfied path

       # Return Value:
       # Relative path wrt the path specified
  
       variable a_global_sim_vars

       # make sure we are dealing with a valid relative_to directory. If regular file or is not a directory, get directory
       if { [file isfile $relative_to] || ![file isdirectory $relative_to] } {
         set relative_to [file dirname $s_relative_to]
       }

       set cwd [file normalize [pwd]]

       if { [file pathtype $file_path_to_convert] eq "relative" } {
         # is relative_to path same as cwd?, just return this path, no further processing required
         if { [string equal $relative_to $cwd] } {
           return $file_path_to_convert
         }
         # the specified path is "relative" but something else, so make it absolute wrt current working dir
         set file_path_to_convert [file join $cwd $file_path_to_convert]
       }

       # is relative_to "relative"? convert to absolute as well wrt cwd
       if { [file pathtype $relative_to] eq "relative" } {
         set relative_to [file join $cwd $relative_to]
       }

       # normalize 
       set file_path_to_convert [file normalize $file_path_to_convert]
       set relative_to          [file normalize $relative_to]

       set file_path $file_path_to_convert
       set file_comps        [file split $file_path]
       set relative_to_comps [file split $relative_to]

       set found_match false
       set index 0

       # compare each dir element of file_to_convert and relative_to, set the flag and
       # get the final index till these sub-dirs matched
       while { [lindex $file_comps $index] == [lindex $relative_to_comps $index] } {
         if { !$found_match } { set found_match true }
         incr index
       }

       # any common dirs found? convert path to relative
       if { $found_match } {
         set parent_dir_path ""
         set rel_index $index
         # keep traversing the relative_to dirs and build "../" levels
         while { [lindex $relative_to_comps $rel_index] != "" } {
           set parent_dir_path "../$parent_dir_path"
           incr rel_index
         }

         # 
         # at this point we have parent_dir_path setup with exact number of sub-dirs to go up
         #

         # now build up part of path which is relative to matched part
         set rel_path ""
         set rel_index $index

         while { [lindex $file_comps $rel_index] != "" } {
           set comps [lindex $file_comps $rel_index]
           if { $rel_path == "" } {
             # first dir
             set rel_path $comps
           } else {
             # append remaining dirs
             set rel_path "${rel_path}/$comps"
           }
           incr rel_index
         }

         # prepend parent dirs, this is the complete resolved path now
         set resolved_path "${parent_dir_path}${rel_path}"

         return $resolved_path
       }

       # no common dirs found, just return the normalized path 
       return $file_path
   }
}