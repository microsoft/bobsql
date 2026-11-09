"use strict";

globalThis.SqlSyntax = (() => {
  const keywords = new Set((
    "ADD ALL ALTER AND ANY AS ASC AUTHORIZATION BACKUP BEGIN BETWEEN BREAK BULK BY " +
    "CASCADE CASE CATCH CHECK CHECKPOINT CLOSE COLLATE COLUMN COMMIT COMMITTED CONSTRAINT " +
    "CONTAINS CONTINUE CREATE CROSS CURRENT CURSOR DATABASE DBCC DEALLOCATE DECLARE DEFAULT " +
    "DELETE DENY DESC DISTINCT DROP ELSE END EXCEPT EXEC EXECUTE EXISTS FETCH FOREIGN FROM " +
    "FULL FUNCTION GO GRANT GROUP HAVING HOLDLOCK IF IMMEDIATE IN INDEX INNER INSERT " +
    "INTERSECT INTO IS ISOLATION JOIN KEY LEFT LEVEL LIKE MERGE MULTI_USER NOCHECK NOCOUNT " +
    "NOLOCK NOT NULL OF OFF ON OPEN OPTION OR ORDER OUTER OUTPUT OVER PERCENT PRIMARY " +
    "PRINT PROC PROCEDURE RAISERROR READ READCOMMITTEDLOCK READPAST READUNCOMMITTED " +
    "REFERENCES REPEATABLE RESTORE RETURN REVOKE RIGHT ROLLBACK ROW ROWLOCK SAVE SCHEMA " +
    "SELECT SERIALIZABLE SET SINGLE_USER SNAPSHOT STATISTICS TABLE THROW TOP TRAN " +
    "TRANSACTION TRIGGER TRUNCATE TRY UNCOMMITTED UNION UNIQUE UPDATE UPDLOCK USE VALUES " +
    "VIEW WAITFOR WHEN WHERE WHILE WITH XLOCK " +
    "ACCELERATED_DATABASE_RECOVERY ALLOW_SNAPSHOT_ISOLATION OPTIMIZED_LOCKING READ_COMMITTED_SNAPSHOT " +
    "BIGINT BINARY BIT CHAR DATE DATETIME DATETIME2 DATETIMEOFFSET DECIMAL FLOAT IMAGE INT " +
    "JSON MONEY NCHAR NTEXT NUMERIC NVARCHAR REAL SMALLDATETIME SMALLINT SMALLMONEY TEXT " +
    "TIME TIMESTAMP TINYINT UNIQUEIDENTIFIER VARBINARY VARCHAR VECTOR"
  ).split(/\s+/));
  const functions = new Set((
    "ABS AVG CAST CEILING CHECKSUM COALESCE CONCAT CONCAT_WS CONVERT COUNT COUNT_BIG " +
    "DATALENGTH DATEADD DATEDIFF DATEDIFF_BIG DATENAME DATEPART DB_ID DB_NAME ERROR_MESSAGE " +
    "ERROR_NUMBER FLOOR GETDATE IIF ISNULL JSON_OBJECT JSON_QUERY JSON_VALUE LEN LTRIM " +
    "MAX MIN NEWID OBJECT_ID OBJECT_NAME PARSENAME POWER REPLACE ROUND ROW_NUMBER RTRIM " +
    "SCOPE_IDENTITY SESSION_CONTEXT SPACE STRING_AGG STRING_SPLIT SUBSTRING SUM " +
    "SYSDATETIME SYSUTCDATETIME TRY_CAST TRY_CONVERT"
  ).split(/\s+/));

  function render(source, className = "") {
    if (typeof source !== "string") throw new TypeError("SQL source must be a string.");
    const pre = document.createElement("pre");
    pre.className = `${className} sql-source`.trim();
    const tokens = /--[^\r\n]*|\/\*|N?'(?:''|[^'])*(?:'|$)|\[(?:\]\]|[^\]])*(?:\]|$)|"(?:""|[^"])*(?:"|$)|@@?[\w$#]+|0x[\da-f]+|(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?|[a-z_#][\w$#]*/gi;
    let end = 0, match;
    while ((match = tokens.exec(source)) !== null) {
      if (match.index > end) pre.append(document.createTextNode(source.slice(end, match.index)));
      let text = match[0], kind = "";
      if (text === "/*") {
        let depth = 1, position = tokens.lastIndex;
        while (position < source.length && depth > 0) {
          if (source.startsWith("/*", position)) { depth++; position += 2; }
          else if (source.startsWith("*/", position)) { depth--; position += 2; }
          else position++;
        }
        tokens.lastIndex = position;
        text = source.slice(match.index, position);
        kind = "comment";
      } else if (text.startsWith("--")) kind = "comment";
      else if (/^N?'/i.test(text)) kind = "string";
      else if (text.startsWith("@")) kind = "variable";
      else if (/^(?:\d|\.\d)/.test(text)) kind = "number";
      else if (keywords.has(text.toUpperCase())) kind = "keyword";
      else if (functions.has(text.toUpperCase()) && /^\s*\(/.test(source.slice(tokens.lastIndex))) kind = "function";
      if (kind) {
        const span = document.createElement("span");
        span.className = `sql-${kind}`;
        span.textContent = text;
        pre.append(span);
      } else pre.append(document.createTextNode(text));
      end = tokens.lastIndex;
    }
    if (end < source.length) pre.append(document.createTextNode(source.slice(end)));
    return pre;
  }

  return { render };
})();
