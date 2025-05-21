/*
 * ECRSrc.h
 *
 *  Created on: 05-Mar-2020
 *      Author: kopresh
 */

#ifndef ECRSRC_ECRSRC_H_
#define ECRSRC_ECRSRC_H_

#define CMD_REGISTER					"A0"
#define CMD_PURCHASE 					"A1"
#define CMD_PURCHASE_CASHBACK 			"A2"
#define CMD_CASH_ADVANCE 				"A3"
#define CMD_PREAUTH 					"A4"
#define CMD_REVERSAL 					"A5"
#define CMD_REFUND 						"A6"
#define CMD_PRECOMP 					"A7"
#define CMD_PREAUTH_EXT 				"A8"
#define CMD_PREAUTH_VOID 				"A9"
#define CMD_SETTLEMENT 					"B1"
#define CMD_PARAM_DOWNLOAD 				"B2"
#define CMD_SET_PARAM 					"B3"
#define CMD_GET_PARAM 					"B4"
#define CMD_SET_TERM_LANG 				"B5"
#define CMD_START_SESSION 				"B6"
#define CMD_END_SESSION 				"B7"
#define CMD_BILL_PAY					"B8"
#define CMD_PRNT_DETAIL_RPORT			"B9"
#define CMD_PRNT_SUMMARY_RPORT			"C1"
#define CMD_REPEAT						"C2"
#define CMD_CHECK_STATUS				"C3"
#define CMD_PARTIAL_DOWNLOAD			"C4"
#define CMD_SNAPSHOT_TOTAL				"C5"

#define STX 							"\x02"
#define ETX 							"\x03"
#define FIELD_SEPERATOR 				"\xFC"
#define DELIMITOR_CHAR 					';'
#define ENDMSG_CHAR 					'!'
#define TIMEOUT_VAL						"120"
#define OUT_DELIMITER					"fffffffc"

#define AMT_SIZE 						12
#define DATETIME_SIZE					12
#define SIGNATURE_SIZE					64
#define REFNUM_SIZE						14
#define TIMEOUT_SIZE					3
#define PRNTFLAG_SIZE					1
#define REQFIELD_SIZE					64
#define LCRBUFFER_SIZE					4
#define RESFIELDS_SIZE					100
#define DELIMITER_SIZE					10
#define RRN_SIZE						12
#define DATE_SIZE						6
#define APPRCODE_SIZE					6
#define PARTIALCOMP_SIZE				1
#define FIELDSEP_SIZE					1
#define CMD_SIZE						2
#define STX_SIZE						1
#define ETX_SIZE						1
#define LCR_SIZE						1
#define LANG_SIZE						1
#define VENDORID_SIZE					2
#define TRSMID_SIZE						6
#define TERMTYPE_SIZE					2
#define KEYINDEX_SIZE					2
#define CASHREGNUM_SIZE					8
#define BILLERID_SIZE					6
#define BILLNUM_SIZE					6
#define ECRNUM_SIZE						6
#define REQATTEMPTNUM_SIZE				3

typedef enum
{
	TYPE_PURCHASE = 0, TYPE_PURCHASE_CASHBACK, TYPE_REFUND, TYPE_PREAUTH, TYPE_PRECOMP, TYPE_PREAUTH_EXT, TYPE_PREAUTH_VOID, TYPE_ADVICE, TYPE_CASH_ADVANCE, TYPE_REVERSAL, TYPE_RECONCILATION, TYPE_PARAM_DOWNLOAD, TYPE_SET_PARAM, TYPE_GET_PARAM, TYPE_SET_TERM_LANG, TYPE_TERM_STATUS, TYPE_PREV_TRAN_DETAILS, TYPE_REGISTER, TYPE_START_SESSION, TYPE_END_SESSION, TYPE_BILL_PAY, TYPE_PRNT_DETAIL_RPORT, TYPE_PRNT_SUMMARY_RPORT, TYPE_REPEAT, TYPE_CHECK_STATUS, TYPE_PARTIAL_DOWNLOAD, TYPE_SNAPSHOT_TOTAL
} ECR_TRANS_TYPE;

void vdParseRequestData(char *inputReqData, char **szReqFields, int *count);
char *getCommand(int tranType);
int validateFieldsCount(int tranType, int fieldsCount);

#endif /* ECRSRC_ECRSRC_H_ */
