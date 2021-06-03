del /f ".\output_sp_reset_stress\*.out" > NUL
rem ostress -dlockhashme -Utest -Ptest -Slpc:. -Q"{call sp_reset_connection()}" -o".\Output_sp_reset_stress" -n1000 -r1000 -l120 -T146 -q
ostress -dlockhashme -E -Slpc:. -Q"{call sp_reset_connection()}" -o".\Output_sp_reset_stress" -n1000 -r10000 -l120 -T146 -q