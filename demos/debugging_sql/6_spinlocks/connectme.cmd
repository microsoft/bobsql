del /f ".\ostress_connectme\*.out" > NUL
rem ostress.exe -Utest -Ptest -Slpc:. -iConnectionDelay.rml -n2000 -q -dlockhashme -l120
"C:\Program Files\Microsoft Corporation\RMLUtils\ostress.exe" -E -Slpc:. -iConnectionDelay.rml -n2000 -q -dlockhashme -l120 -oostress_connectme