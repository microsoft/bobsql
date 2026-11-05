# Regular Expressions (REGEX) in SQL Server 2025

This demo demonstrates the new regular expression support in SQL Server 2025, enabling powerful pattern matching and validation directly in T-SQL.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **SQL Server Management Studio (SSMS)**

## Overview

SQL Server 2025 introduces native regular expression functions that provide:
- Pattern matching beyond LIKE capabilities
- Data validation using regex patterns
- CHECK constraints with regex validation
- Industry-standard regex syntax
- Efficient pattern-based searching

## Files

| File | Purpose |
|------|---------|
| `01_regex_ddl.sql` | Creates database and table with REGEXP_LIKE CHECK constraints |
| `01_regex_ddl_ver2.sql` | Alternative version of DDL with regex validation |
| `02_phone_test.sql` | Tests phone number regex validation |
| `03_find_email.sql` | Demonstrates email pattern matching queries |

## Step-by-Step Instructions

### Step 1: Create Database with Regex Validation
```sql
-- Run: 01_regex_ddl.sql
```

This script creates an HR database with an EMPLOYEES table featuring:
- **Email Validation** - CHECK constraint using REGEXP_LIKE for valid email format
- **Phone Number Validation** - CHECK constraint for US phone number formats

**Email Regex Pattern:**
```regex
^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$
```

This validates:
- Local part: letters, numbers, and special characters (. _ % + -)
- @ symbol
- Domain name with letters, numbers, dots, and hyphens
- Top-level domain with at least 2 letters

**Phone Number Regex Pattern:**
```regex
^(?:\+\d{1,3}[ -]?)?(?:\([2-9]\d{2}\)[ -]?\d{3}-\d{4}|[2-9]\d{2}[ -]?\d{3}-\d{4})$
```

This validates:
- Optional international prefix (+1, +44, etc.)
- US format: (XXX) XXX-XXXX or XXX-XXX-XXXX
- First digit must be 2-9 (valid US area codes)

The script includes detailed comments explaining each part of the regex patterns.

### Step 2: Test Phone Number Validation
```sql
-- Run: 02_phone_test.sql
```

Tests various phone number formats:
- Valid formats that should be accepted
- Invalid formats that should be rejected
- Edge cases and boundary conditions

This demonstrates how CHECK constraints with REGEXP_LIKE prevent invalid data from being inserted.

### Step 3: Find Records with Email Patterns
```sql
-- Run: 03_find_email.sql
```

Demonstrates using REGEXP_LIKE in queries to:
- Find email addresses from specific domains
- Match email patterns
- Filter data based on regex patterns
- Perform complex pattern-based searches

### Alternative Version

The `01_regex_ddl_ver2.sql` file provides an alternative implementation with potentially different regex patterns or validation rules. Compare both versions to see different approaches to regex validation.

## What You'll Learn

- How to use REGEXP_LIKE for pattern matching
- Creating CHECK constraints with regular expressions
- Writing regex patterns for common validation scenarios
- Using regex in WHERE clauses for querying
- Benefits of regex over traditional LIKE patterns
- Understanding regex syntax and pattern components

## Key Concepts

**REGEXP_LIKE:** A function that returns TRUE if a string matches a regular expression pattern.

**Regular Expression:** A sequence of characters that define a search pattern, used for pattern matching and validation.

**CHECK Constraint:** A database constraint that uses REGEXP_LIKE to validate data before allowing INSERT or UPDATE operations.

**Pattern Matching:** Finding strings that match a specific pattern, going beyond simple wildcard matching.

## Regular Expression Components

Common regex elements used in these demos:

| Symbol | Meaning | Example |
|--------|---------|---------|
| `^` | Start of string | `^abc` matches strings starting with "abc" |
| `$` | End of string | `xyz$` matches strings ending with "xyz" |
| `[A-Za-z]` | Character class | Any uppercase or lowercase letter |
| `[0-9]` or `\d` | Digit | Any number 0-9 |
| `+` | One or more | `a+` matches "a", "aa", "aaa", etc. |
| `*` | Zero or more | `a*` matches "", "a", "aa", etc. |
| `?` | Optional (zero or one) | `colou?r` matches "color" or "colour" |
| `{n,m}` | Between n and m occurrences | `\d{2,4}` matches 2-4 digits |
| `()` | Grouping | `(abc)+` matches "abc", "abcabc", etc. |
| `|` | Alternation (OR) | `cat|dog` matches "cat" or "dog" |
| `\.` | Literal dot | Matches actual period character |

## Benefits Over LIKE

Traditional LIKE limitations:
- Only supports simple wildcards (%, _)
- Cannot validate complex patterns
- Limited pattern flexibility

REGEXP_LIKE advantages:
✅ **Complex Patterns** - Match sophisticated patterns  
✅ **Data Validation** - Enforce format rules at database level  
✅ **Industry Standard** - Use familiar regex syntax  
✅ **Powerful Searches** - Find data matching complex criteria  
✅ **Better Validation** - More precise than LIKE patterns  

## Common Use Cases

- **Email Validation** - Ensure valid email format
- **Phone Number Validation** - Enforce phone number standards
- **ZIP/Postal Code Validation** - Validate address formats
- **Credit Card Format** - Basic format validation (not security validation)
- **URL Validation** - Check URL structure
- **Social Security Numbers** - Validate SSN format
- **Product Codes** - Enforce SKU patterns
- **License Plates** - Validate registration formats
- **IP Addresses** - Check IP format
- **Date Formats** - Validate custom date patterns

## Example Patterns

**Email:**
```regex
^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$
```

**US Phone:**
```regex
^\d{3}-\d{3}-\d{4}$
```

**ZIP Code (5 or 9 digit):**
```regex
^\d{5}(-\d{4})?$
```

**URL:**
```regex
^https?://[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/.*)?$
```

**Strong Password (min 8 chars, upper, lower, digit, special):**
```regex
^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$
```

## Performance Considerations

- **Regex can be CPU-intensive** for complex patterns on large datasets
- **Use indexes when possible** - Consider computed columns with indexes for frequently searched patterns
- **Keep patterns efficient** - Avoid overly complex regex when simpler patterns suffice
- **Test performance** - Compare regex vs. other validation methods for your workload

## Troubleshooting

**Pattern Not Matching:** Test your regex pattern with online regex testers first (regex101.com, etc.).

**CHECK Constraint Violation:** Review the error message and verify your data matches the expected pattern.

**Performance Issues:** Consider simplifying regex patterns or using computed columns with regular indexes.

**Syntax Errors:** Ensure special characters are properly escaped with backslashes.

## Next Steps

- Build comprehensive data validation rules using regex
- Create a library of common regex patterns for your organization
- Implement regex-based data quality checks
- Combine regex with other SQL Server validation features
- Use regex for data cleansing and transformation
- Explore regex for log analysis and pattern detection
