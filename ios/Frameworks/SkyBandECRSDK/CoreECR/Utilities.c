/*
 * Utilities.c
 *
 *  Created on: Feb 20, 2020
 *      Author: Kopresh
 */
#include <stdio.h>
#include <string.h>
#include "Utilities.h"

void hexDataPrint(char * headerString, unsigned char * inputBuffer, int numBytes)
{
    int inIndex = 0, inReminder, inNumBlks, inCtr, inPrintBlk;
    unsigned char ucDisplayBuf[MAX_DEBUG_BUF_SIZE + 1];
    unsigned char * pucBuf = inputBuffer;

    inNumBlks = numBytes / (MAX_DEBUG_BUF_SIZE / 2);
    inReminder = numBytes % (MAX_DEBUG_BUF_SIZE / 2);

    if (inNumBlks)     // minimum 1 block of 512 bytes is there
        inPrintBlk = (MAX_DEBUG_BUF_SIZE / 2);
    else
        inPrintBlk = inReminder;

    if (inReminder)
        inNumBlks++;

    if (numBytes > (MAX_DEBUG_BUF_SIZE / 2))
        printf("Total buffer length %d...Printing max only %d chars in one go", numBytes, (MAX_DEBUG_BUF_SIZE / 2));

    inReminder = numBytes;

    for(inCtr = 1; inCtr <= inNumBlks; inCtr++)
    {
        for (inIndex = 0; inIndex < inPrintBlk; inIndex++)
            sprintf((char*) &ucDisplayBuf[inIndex * 2], "%02X", *pucBuf++);

        printf("%s, Part %d, Len %d: %s", headerString,inCtr, inPrintBlk, ucDisplayBuf);

        inReminder -= inPrintBlk;

        if (inReminder < (MAX_DEBUG_BUF_SIZE / 2))
            inPrintBlk = inReminder;
    }

    return;
}

void ascToHexConv (unsigned char *outp, unsigned char *inp, int iLength)
{
    int i;
    int iAux1, iAux2;

    i = 0;

    // iLength is odd, so do some adjustment to put a zero at the start
    if (iLength & 0x01)
    {
        iAux1 = inp[0] - '0';
        if (iAux1 >  9) iAux1 -= 7;
        if (iAux1 > 15) iAux1 -= 39;

        outp[0] = (unsigned char)iAux1;

        i++;
    }

    for (; i < iLength; i++)
    {
        iAux1 = inp[i] - '0';
        if (iAux1 >  9) iAux1 -= 7;
        if (iAux1 > 15) iAux1 -= 39;

        iAux2 = inp[++i] - '0';
        if (iAux2 >  9) iAux2 -= 7;
        if (iAux2 > 15) iAux2 -= 39;

        iAux1   = iAux1 << 4;
        iAux1  += iAux2;
        outp[i / 2] = (unsigned char)iAux1;
    }

    return;
}

void xorOpBtwnChars (unsigned char *pbt_Data1, int i_DataLen, int *output)
{
        int i = 0, result = 0;

        for (i = 0; i < i_DataLen; i++)
        {
            *output = result ^ pbt_Data1[i];
            result = *output;
        }
}
