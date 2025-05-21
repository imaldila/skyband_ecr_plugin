#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

/*********************************************************************************************
* @func void | pack |
* This routine takes ECR input string data and gives output in packed format
*
* @parm char * | inputReqData |
*       This is ECR input string data
*
* @parm int | transactionType |
*       This is input transaction type
*
* @parm char * | szSignature |
*       This is input signature data
*
* @parm char * | szEcrBuffer |
*       This is output in packed format
*
* @rdesc Returns number of input request data
* @end
**********************************************************************************************/
EXPORT int pack(char *inputReqData, int transactionType, char *szSignature, char *szEcrBuffer);


/*********************************************************************************************
* @func void | parse |
* This routine takes data in packed input format and gives response fields in char array
*
* @parm char * | respData |
*       This is packed input data
*
* @parm char * | respOutData |
*       This is the parsed output response data.
*
* @rdesc Returns nothing
* @end
**********************************************************************************************/
EXPORT void parse(char *respData, char *respOutData);


