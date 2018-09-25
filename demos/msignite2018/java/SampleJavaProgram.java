import java.io.*;
import java.util.Date;
import java.text.SimpleDateFormat;

public class SampleJavaProgram {   
    static public int[] inputDataCol1 = new int[1];
    static public int[] inputDataCol2 = new int[1];
    static public boolean[][] inputNullMap = new boolean[1][1];
    static public int[] outputDataCol1;
    static public double[] outputDataCol2;    
    static public boolean[][] outputNullMap;
    static public int numberOfRows;
    static public short numberOfOutputCols;

    // Multiply each column by arbitary number
    public static void MultiplyColumnByParam() {
		numberOfRows = inputDataCol1.length;
		System.out.printf("Number of rows: %d\n", numberOfRows);

		outputDataCol1 = new int[numberOfRows];
		outputDataCol2 = new double[numberOfRows];
		numberOfOutputCols = 2;
		System.out.printf("Number of cols in null map: %d\n", inputNullMap.length);
		System.out.printf("Number of rows in null map: %d\n", inputNullMap[0].length);

		for (int i = 0; i < numberOfRows; i++) {
			System.out.printf("input data: %d %d\n", inputDataCol1[i], inputDataCol2[i]);
			System.out.printf("Null map value at col 1 index %d: %b\n", i, inputNullMap[0][i]);
			outputDataCol1[i] = 2 * inputDataCol1[i];

			System.out.printf("Null map value at col 2 index %d: %b\n", i, inputNullMap[1][i]);
			outputDataCol2[i] = 3 * inputDataCol2[i];
		}
		
		for (int i = 0; i < numberOfRows; i++) {
			System.out.printf("output data: %d %.1f\n", outputDataCol1[i], outputDataCol2[i]);
		}

		outputNullMap = new boolean[numberOfOutputCols][numberOfRows];
		for (int i = 0; i < numberOfOutputCols; i++) {
			for (int j = 0; j < numberOfRows; j++) {
				outputNullMap[i][j] = inputNullMap[i][j];
			}
		}             
    }
}
