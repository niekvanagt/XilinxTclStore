# Set the File Directory to the current directory location of the script
set file_dir [file normalize [file dirname [info script]]]

# Set the Xilinx Tcl App Store Repository to the current repository location
puts "== Unit Test directory: $file_dir"

# Set the Name to the name of the script
set name [file rootname [file tail [info script]]]

# Load the Design Checkpoint for the specific test
open_checkpoint "$file_dir/src/write_slr_pblock_xdc/$name.dcp"

# Run the write_slr_pblock_xdc script and verify that no error was reported
if {[catch { ::tclapp::xilinx::designutils::write_slr_pblock_xdc -file $name.xdc } catchErrorString]} {
    error [format " -E- Unit test $name failed: %s" $catchErrorString]   
}

# Clean up the generated files from the script run
foreach generatedFileName [glob -nocomplain $name.xdc] { file delete -force $generatedFileName }

return 0
