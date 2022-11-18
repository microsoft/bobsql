// crash.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <iostream>
#include <windows.h>
#include <exception>

int main()
{
    std::cout << "Hello World!\n";
    int* x = (int*)0;

    //__try
    //{
        *x = 1;
    //}
    //__except(EXCEPTION_EXECUTE_HANDLER)
    //{
    //    std::cout << "SEH block." << std::endl;
    //
    //}
    return 0;



}
