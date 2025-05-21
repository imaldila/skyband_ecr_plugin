/*
 * ECRSrc.c
 *
 *  Created on: 05-Mar-2020
 *      Author: kopresh
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ECRSrc.h"
#include "Utilities.h"

extern void hexDataPrint(char * headerString, unsigned char * inputBuffer, int numBytes);
extern void ascToHexConv (unsigned char *outp, unsigned char *inp, int iLength);
extern void xorOpBtwnChars (unsigned char *pbt_Data1, int i_DataLen, int *output);

void vdParseRequestData(char *inputReqData, char **szReqFields, int *count)
{
	char szItem[100];
	int inReqDataIndex = 0, inItemsCount = 0, inFieldIndex = 0;

	memset(szItem, 0x00, sizeof(szItem));
	for(inReqDataIndex=0; inReqDataIndex<strlen(inputReqData); inReqDataIndex++)
	{
		if(inputReqData[inReqDataIndex] == DELIMITOR_CHAR)
		{
			memcpy(szReqFields[inItemsCount], szItem, strlen(szItem));
			inItemsCount++;
			memset(szItem, 0x00, sizeof(szItem));
			inFieldIndex = 0;
		}
		if(inputReqData[inReqDataIndex] != DELIMITOR_CHAR)
		{
			szItem[inFieldIndex] = inputReqData[inReqDataIndex];
			inFieldIndex++;
			if(inputReqData[inReqDataIndex] == ENDMSG_CHAR)
			{
				memcpy(szReqFields[inItemsCount], szItem, strlen(szItem)-1);
				inItemsCount++;
			}
		}
	}
	*count = inItemsCount;
}

char *getCommand(int tranType)
{
    //printf("Get Command\n");
    switch(tranType)
    {
        case TYPE_PURCHASE:
            return CMD_PURCHASE;    //Purchase

        case TYPE_PURCHASE_CASHBACK:
            return CMD_PURCHASE_CASHBACK;     //Purchase cashback

        case TYPE_REFUND:
            return CMD_REFUND;        // Refund

        case TYPE_PREAUTH:
            return CMD_PREAUTH;        //Pre-authorization

        case TYPE_REVERSAL:
            return CMD_REVERSAL;        //Reversal

        case TYPE_PRECOMP:
            return CMD_PRECOMP;        //Pre-Auth Completion

        case TYPE_PREAUTH_EXT:
            return CMD_PREAUTH_EXT;     //Pre-Auth Extension

        case TYPE_PREAUTH_VOID:
            return CMD_PREAUTH_VOID;     //Pre-Auth VOID

        case TYPE_CASH_ADVANCE:
            return CMD_CASH_ADVANCE;    //Cash Advance

        case TYPE_RECONCILATION:
            return CMD_SETTLEMENT;    //Settlement

        case TYPE_PARAM_DOWNLOAD:
            return CMD_PARAM_DOWNLOAD;    //Parameter Download

        case TYPE_SET_PARAM:
            return CMD_SET_PARAM;    //Get Parameter

        case TYPE_GET_PARAM:
            return CMD_GET_PARAM;    //Get Parameter

        case TYPE_SET_TERM_LANG:
            return CMD_SET_TERM_LANG;    //Set Terminal Language

        case TYPE_REGISTER:
            return CMD_REGISTER;    //Register

        case TYPE_START_SESSION:
            return CMD_START_SESSION;    //Start Session

        case TYPE_END_SESSION:
            return CMD_END_SESSION;        //End Session

        case TYPE_BILL_PAY:
            return CMD_BILL_PAY;        //Bill Pay

        case TYPE_PRNT_DETAIL_RPORT:
            return CMD_PRNT_DETAIL_RPORT;    //Print detail report

        case TYPE_PRNT_SUMMARY_RPORT:
            return CMD_PRNT_SUMMARY_RPORT;    //Print summary report

        case TYPE_REPEAT:
            return CMD_REPEAT;    //Repeat

        case TYPE_CHECK_STATUS:
            return CMD_CHECK_STATUS;    //Check Status

		case TYPE_PARTIAL_DOWNLOAD:
			return CMD_PARTIAL_DOWNLOAD;	//Partial Download

		case TYPE_SNAPSHOT_TOTAL:
			return CMD_SNAPSHOT_TOTAL;	//Snapshot Total

		default:
			break;
	}
	return "";
}

#define PURCHASE_FIELDS_COUNT 			4
#define PURCHASE_CASHBACK_FIELDS_COUNT 	5
#define REFUND_FIELDS_COUNT 			6
#define PREAUTH_FIELDS_COUNT 			4
#define PRECOMP_FIELDS_COUNT 			8
#define PREAUTH_EXT_FIELDS_COUNT 		6
#define PREAUTH_VOID_FIELDS_COUNT 		7
#define CASH_ADVANCE_FIELDS_COUNT 		4
#define REVERSAL_FIELDS_COUNT 			3
#define RECONCILATION_FIELDS_COUNT 		3
#define PARAM_DOWNLOAD_FIELDS_COUNT 	2
#define SET_PARAM_FIELDS_COUNT 			7
#define GET_PARAM_FIELDS_COUNT 			2
#define REGISTER_FIELDS_COUNT 			2
#define START_SESSION_FIELDS_COUNT 		2
#define END_SESSION_FIELDS_COUNT 		2
#define BILL_PAY_FIELDS_COUNT 			6
#define PRNT_DETAIL_RPORT_FIELDS_COUNT 	2
#define PRNT_SUMMARY_RPORT_FIELDS_COUNT 3
#define REPEAT_FIELDS_COUNT 			3
#define CHECK_STATUS_FIELDS_COUNT 		2
#define PARTIAL_DOWNLOAD_FIELDS_COUNT 	2
#define SNAPSHOT_TOTAL_FIELDS_COUNT		2

int validateFieldsCount(int tranType, int fieldsCount)
{
	int tranTypeFieldsCount = -1;
	switch(tranType)
	{
		case TYPE_PURCHASE:
			tranTypeFieldsCount = PURCHASE_FIELDS_COUNT;	//Purchase
			break;

		case TYPE_PURCHASE_CASHBACK:
			tranTypeFieldsCount = PURCHASE_CASHBACK_FIELDS_COUNT; 	//Purchase cashback
			break;

		case TYPE_REFUND:
			tranTypeFieldsCount = REFUND_FIELDS_COUNT;		// Refund
			break;

		case TYPE_PREAUTH:
			tranTypeFieldsCount = PREAUTH_FIELDS_COUNT;		//Pre-authorization
			break;

		case TYPE_REVERSAL:
			tranTypeFieldsCount = REVERSAL_FIELDS_COUNT;		//Reversal
			break;

		case TYPE_PRECOMP:
			tranTypeFieldsCount = PRECOMP_FIELDS_COUNT;		//Pre-Auth Completion
			break;

		case TYPE_PREAUTH_EXT:
			tranTypeFieldsCount = PREAUTH_EXT_FIELDS_COUNT; 	//Pre-Auth Extension
			break;

		case TYPE_PREAUTH_VOID:
			tranTypeFieldsCount = PREAUTH_VOID_FIELDS_COUNT; 	//Pre-Auth VOID
			break;

		case TYPE_CASH_ADVANCE:
			tranTypeFieldsCount = CASH_ADVANCE_FIELDS_COUNT;	//Cash Advance
			break;

		case TYPE_RECONCILATION:
			tranTypeFieldsCount = RECONCILATION_FIELDS_COUNT;	//Settlement
			break;

		case TYPE_PARAM_DOWNLOAD:
			tranTypeFieldsCount = PARAM_DOWNLOAD_FIELDS_COUNT;	//Parameter Download
			break;

		case TYPE_SET_PARAM:
			tranTypeFieldsCount = SET_PARAM_FIELDS_COUNT;	//Get Parameter
			break;

		case TYPE_GET_PARAM:
			tranTypeFieldsCount = GET_PARAM_FIELDS_COUNT;	//Get Parameter
			break;

		case TYPE_REGISTER:
			tranTypeFieldsCount = REGISTER_FIELDS_COUNT;	//Register
			break;

		case TYPE_START_SESSION:
			tranTypeFieldsCount = START_SESSION_FIELDS_COUNT;	//Start Session
			break;

		case TYPE_END_SESSION:
			tranTypeFieldsCount = END_SESSION_FIELDS_COUNT;		//End Session
			break;

		case TYPE_BILL_PAY:
			tranTypeFieldsCount = BILL_PAY_FIELDS_COUNT;		//Bill Pay
			break;

		case TYPE_PRNT_DETAIL_RPORT:
			tranTypeFieldsCount = PRNT_DETAIL_RPORT_FIELDS_COUNT;	//Print detail report
			break;

		case TYPE_PRNT_SUMMARY_RPORT:
			tranTypeFieldsCount = PRNT_SUMMARY_RPORT_FIELDS_COUNT;	//Print summary report
			break;

		case TYPE_REPEAT:
			tranTypeFieldsCount = REPEAT_FIELDS_COUNT;	//Repeat
			break;

		case TYPE_CHECK_STATUS:
			tranTypeFieldsCount = CHECK_STATUS_FIELDS_COUNT;	//Check Status
			break;

		case TYPE_PARTIAL_DOWNLOAD:
			tranTypeFieldsCount = PARTIAL_DOWNLOAD_FIELDS_COUNT;	//Partial Download
			break;

		case TYPE_SNAPSHOT_TOTAL:
			tranTypeFieldsCount = SNAPSHOT_TOTAL_FIELDS_COUNT;	//Snapshot Total
			break;

		default:
			break;
	}
	printf("\ntranType = %d, fieldsCount = %d, tranTypeFieldsCount = %d\n", tranType, fieldsCount, tranTypeFieldsCount);
	if(tranTypeFieldsCount == fieldsCount)
		return tranTypeFieldsCount;
	else
		return -1;
}
