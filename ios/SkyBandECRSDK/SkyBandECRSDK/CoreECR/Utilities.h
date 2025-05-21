/*
 * Utilities.h
 *
 *  Created on: Feb 20, 2020
 *      Author: Kopresh
 */

#ifndef SOURCE_UTILS_UTILITIES_H_
#define SOURCE_UTILS_UTILITIES_H_

#define MAX_DEBUG_BUF_SIZE        1024
#define TWELVE_ZEROS             "000000000000"

void hexDataPrint(char * headerString, unsigned char * inputBuffer, int numBytes);
void ascToHexConv (unsigned char *outp, unsigned char *inp, int iLength);
void xorOpBtwnChars (unsigned char *pbt_Data1, int i_DataLen, int *output);

#endif /* SOURCE_UTILS_UTILITIES_H_ */
