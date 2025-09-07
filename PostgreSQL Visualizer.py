#!/usr/bin/env python3
"""
Generate an ERD for a PostgreSQL database using SQLAlchemy reflection + Graphviz.

Example:
  python pg_erd.py \
    --db postgresql+psycopg2://user:pass@localhost:5432/mydb \
    --out erd.svg \
    --format svg \
    --include-schemas public

Notes:
- Requires Graphviz installed on your system and the `graphviz` Python package.
- By default excludes internal schemas: pg_catalog, information_schema.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
from graphviz import Digraph
from sqlalchemy import create_engine, MetaData
from sqlalchemy.engine import Engine
from sqlalchemy.engine.reflection import Inspector
from sqlalchemy import inspect


# -------- Data Models ---------------------------------------------------------

@dataclass
class ColumnInfo:
    name: str
    typeName: str
    isPrimaryKey: bool
    isForeignKey: bool
    isNullable: bool
    default: Optional[str]


@dataclass
class ForeignKeyInfo:
    name: Optional[str]
    sourceTable: str
    sourceSchema: Optional[str]
    sourceColumns: List[str]
    targetTable: str
    targetSchema: Optional[str]
    targetColumns: List[str]


@dataclass
class TableInfo:
    name: str
    schema: Optional[str]
    columns: List[ColumnInfo]
    primaryKeyCols: List[str]
    foreignKeys: List[ForeignKeyInfo]


# -------- SQL Parsing ---------------------------------------------------------

def parseSqlFile(filePath: str) -> List[TableInfo]:
    """Parse SQL DDL statements from a file and extract table information."""
    with open(filePath, 'r', encoding='utf-8') as f:
        sql_content = f.read()
    
    return parseSqlContent(sql_content)

def parseSqlContent(sqlContent: str) -> List[TableInfo]:
    """Parse SQL DDL statements and extract table information."""
    tables: List[TableInfo] = []
    
    # Remove comments (both -- and /* */ style)
    sqlContent = re.sub(r'--.*$', '', sqlContent, flags=re.MULTILINE)
    sqlContent = re.sub(r'/\*.*?\*/', '', sqlContent, flags=re.DOTALL)
    
    # Remove DO $$ ... END $$; blocks (PostgreSQL procedural blocks)
    sqlContent = re.sub(r'DO\s+\$\$.*?\$\$;', '', sqlContent, flags=re.DOTALL | re.IGNORECASE)
    
    # Remove CREATE TYPE statements
    sqlContent = re.sub(r'CREATE\s+TYPE\s+.*?;', '', sqlContent, flags=re.DOTALL | re.IGNORECASE)
    
    # Remove CREATE INDEX statements
    sqlContent = re.sub(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+.*?;', '', sqlContent, flags=re.DOTALL | re.IGNORECASE)
    
    # Normalize whitespace
    sqlContent = re.sub(r'\s+', ' ', sqlContent).strip()
    
    # Find CREATE TABLE statements (handle quoted table names)
    createTablePattern = r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(\w+)\.)?(?:"?(\w+)"?)\s*\((.*?)\)(?:\s*INHERITS\s*\([^)]+\))?(?:\s*WITH\s*\([^)]+\))?(?:\s*TABLESPACE\s+\w+)?;'
    
    matches = re.finditer(createTablePattern, sqlContent, re.IGNORECASE | re.DOTALL)
    
    for match in matches:
        schema = match.group(1) if match.group(1) else 'public'
        tableName = match.group(2)
        columnsDef = match.group(3)
        
        table = parseTableDefinition(schema, tableName, columnsDef, sqlContent)
        if table:
            tables.append(table)
    
    # Parse foreign key relationships
    addForeignKeysFromSql(tables, sqlContent)
    
    return tables

def parseTableDefinition(schema: str, tableName: str, columnsDef: str, fullSql: str) -> Optional[TableInfo]:
    """Parse a single table definition from CREATE TABLE statement."""
    columns: List[ColumnInfo] = []
    primaryKeyCols: List[str] = []
    foreignKeys: List[ForeignKeyInfo] = []
    
    # Split column definitions (handle nested parentheses)
    columnDefs = splitColumnDefinitions(columnsDef)
    
    for colDef in columnDefs:
        colDef = colDef.strip()
        if not colDef:
            continue
            
        # Skip table constraints (PRIMARY KEY, FOREIGN KEY, etc.)
        if re.match(r'^\s*(PRIMARY\s+KEY|FOREIGN\s+KEY|UNIQUE|CHECK|CONSTRAINT)', colDef, re.IGNORECASE):
            # Handle table-level PRIMARY KEY constraint
            pkMatch = re.search(r'PRIMARY\s+KEY\s*\(\s*([^)]+)\s*\)', colDef, re.IGNORECASE)
            if pkMatch:
                pkCols = [col.strip().strip('"') for col in pkMatch.group(1).split(',')]
                primaryKeyCols.extend(pkCols)
            continue
        
        # Parse column definition
        column = parseColumnDefinition(colDef)
        if column:
            columns.append(column)
            if column.isPrimaryKey:
                primaryKeyCols.append(column.name)
    
    return TableInfo(
        name=tableName,
        schema=schema,
        columns=columns,
        primaryKeyCols=primaryKeyCols,
        foreignKeys=foreignKeys
    )

def splitColumnDefinitions(columnsDef: str) -> List[str]:
    """Split column definitions handling nested parentheses."""
    parts = []
    current = ""
    parenLevel = 0
    
    for char in columnsDef:
        if char == '(':
            parenLevel += 1
        elif char == ')':
            parenLevel -= 1
        elif char == ',' and parenLevel == 0:
            parts.append(current.strip())
            current = ""
            continue
        current += char
    
    if current.strip():
        parts.append(current.strip())
    
    return parts

def parseColumnDefinition(colDef: str) -> Optional[ColumnInfo]:
    """Parse a single column definition."""
    # Basic pattern: column_name data_type [constraints...]
    parts = colDef.strip().split()
    if len(parts) < 2:
        return None
    
    columnName = parts[0].strip('"')
    
    # Handle data types (including PostgreSQL-specific ones)
    dataType = parts[1]
    
    # Handle data types with parameters like VARCHAR(255), NUMERIC(7,4), CHAR(3)
    typeEndIdx = 1
    if len(parts) > 2 and parts[2].startswith('('):
        i = 2
        while i < len(parts) and not parts[i].endswith(')'):
            dataType += ' ' + parts[i]
            i += 1
        if i < len(parts):
            dataType += ' ' + parts[i]
            typeEndIdx = i
    
    # Handle array types like TEXT[]
    if len(parts) > typeEndIdx + 1 and parts[typeEndIdx + 1].startswith('['):
        dataType += parts[typeEndIdx + 1]
        typeEndIdx += 1
    
    # Parse constraints from remaining parts
    constraintStr = ' '.join(parts[typeEndIdx + 1:])
    isPrimaryKey = bool(re.search(r'\bPRIMARY\s+KEY\b', constraintStr, re.IGNORECASE))
    isNullable = not bool(re.search(r'\bNOT\s+NULL\b', constraintStr, re.IGNORECASE))
    
    # Parse default value (handle complex defaults like now(), CURRENT_TIMESTAMP, etc.)
    defaultMatch = re.search(r'\bDEFAULT\s+([^,\s]+(?:\([^)]*\))?(?:\s+[^,\s]*)?)', constraintStr, re.IGNORECASE)
    default = defaultMatch.group(1) if defaultMatch else None
    
    return ColumnInfo(
        name=columnName,
        typeName=dataType,
        isPrimaryKey=isPrimaryKey,
        isForeignKey=False,  # Will be set later when parsing FK constraints
        isNullable=isNullable,
        default=default
    )

def addForeignKeysFromSql(tables: List[TableInfo], sqlContent: str):
    """Parse and add foreign key relationships from SQL content."""
    # Create lookup for tables
    tableMap = {(t.schema, t.name): t for t in tables}
    
    # First, parse inline REFERENCES clauses
    addInlineForeignKeys(tables, tableMap, sqlContent)
    
    # Then, parse table-level FOREIGN KEY constraints
    fkPattern = r'(?:CONSTRAINT\s+(\w+)\s+)?FOREIGN\s+KEY\s*\(\s*([^)]+)\s*\)\s+REFERENCES\s+(?:(\w+)\.)?(?:"?(\w+)"?)\s*\(\s*([^)]+)\s*\)'
    
    matches = re.finditer(fkPattern, sqlContent, re.IGNORECASE)
    
    for match in matches:
        constraintName = match.group(1)
        sourceColumns = [col.strip().strip('"') for col in match.group(2).split(',')]
        targetSchema = match.group(3) if match.group(3) else 'public'
        targetTable = match.group(4)
        targetColumns = [col.strip().strip('"') for col in match.group(5).split(',')]
        
        # Find which table this FK belongs to (search backwards for CREATE TABLE)
        beforeMatch = sqlContent[:match.start()]
        createTableMatch = None
        for tableMatch in re.finditer(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(\w+)\.)?(?:"?(\w+)"?)', beforeMatch, re.IGNORECASE):
            createTableMatch = tableMatch
        
        if createTableMatch:
            sourceSchema = createTableMatch.group(1) if createTableMatch.group(1) else 'public'
            sourceTable = createTableMatch.group(2)
            
            # Add FK to source table
            sourceTableInfo = tableMap.get((sourceSchema, sourceTable))
            if sourceTableInfo:
                fk = ForeignKeyInfo(
                    name=constraintName,
                    sourceTable=sourceTable,
                    sourceSchema=sourceSchema,
                    sourceColumns=sourceColumns,
                    targetTable=targetTable,
                    targetSchema=targetSchema,
                    targetColumns=targetColumns
                )
                sourceTableInfo.foreignKeys.append(fk)
                
                # Mark source columns as foreign keys
                for col in sourceTableInfo.columns:
                    if col.name in sourceColumns:
                        col.isForeignKey = True

def extractTableBody(sqlContent: str, schema: str, tableName: str) -> Optional[str]:
    """Extract table body handling nested parentheses properly."""
    # Find the start of CREATE TABLE
    pattern = rf'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:{re.escape(schema)}\.)?(?:"{re.escape(tableName)}"|{re.escape(tableName)})\s*\('
    match = re.search(pattern, sqlContent, re.IGNORECASE)
    if not match:
        return None
    
    start_pos = match.end() - 1  # Position of opening (
    paren_count = 1
    pos = start_pos + 1
    
    while pos < len(sqlContent) and paren_count > 0:
        if sqlContent[pos] == '(':
            paren_count += 1
        elif sqlContent[pos] == ')':
            paren_count -= 1
        pos += 1
    
    if paren_count == 0:
        return sqlContent[start_pos + 1:pos - 1]
    return None

def addInlineForeignKeys(tables: List[TableInfo], tableMap: Dict[Tuple[Optional[str], str], TableInfo], sqlContent: str):
    """Parse inline REFERENCES clauses in column definitions."""
    # Pattern for inline REFERENCES: column_name type REFERENCES table(column)
    inlineRefPattern = r'"?(\w+)"?\s+\w+(?:\([^)]+\))?\s+(?:[^,]*?)\bREFERENCES\s+(?:(\w+)\.)?(?:"?(\w+)"?)\s*\(\s*"?(\w+)"?\s*\)'
    
    # Process each table
    for table in tables:
        # Extract the table body properly handling nested parentheses
        tableBody = extractTableBody(sqlContent, table.schema or 'public', table.name)
        
        if tableBody:
            # Process each line separately to avoid multiline matching issues
            lines = tableBody.strip().split('\n')
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                
                # Find inline REFERENCES in this line
                for refMatch in re.finditer(inlineRefPattern, line, re.IGNORECASE):
                    sourceColumn = refMatch.group(1)
                    targetSchema = refMatch.group(2) if refMatch.group(2) else 'public'
                    targetTable = refMatch.group(3)
                    targetColumn = refMatch.group(4)
                    
                    # Create foreign key relationship
                    fk = ForeignKeyInfo(
                        name=None,  # Inline FKs usually don't have explicit names
                        sourceTable=table.name,
                        sourceSchema=table.schema,
                        sourceColumns=[sourceColumn],
                        targetTable=targetTable,
                        targetSchema=targetSchema,
                        targetColumns=[targetColumn]
                    )
                    table.foreignKeys.append(fk)
                    
                    # Mark source column as foreign key
                    for col in table.columns:
                        if col.name == sourceColumn:
                            col.isForeignKey = True


# -------- Reflection ----------------------------------------------------------

DEFAULT_EXCLUDED_SCHEMAS = {"pg_catalog", "information_schema"}

def getInspector(dbUrl: str) -> Inspector:
    engine: Engine = create_engine(dbUrl)
    return inspect(engine)

def listSchemas(inspector: Inspector, includeSchemas: Optional[List[str]], excludeSchemas: Optional[List[str]]) -> List[str]:
    allSchemas = inspector.get_schema_names()
    if includeSchemas:
        wanted = [s for s in allSchemas if s in set(includeSchemas)]
    else:
        wanted = [s for s in allSchemas if s not in DEFAULT_EXCLUDED_SCHEMAS]
    if excludeSchemas:
        wanted = [s for s in wanted if s not in set(excludeSchemas)]
    return wanted

def reflectTable(inspector: Inspector, schema: str, tableName: str) -> TableInfo:
    colsData = inspector.get_columns(tableName, schema=schema)
    pkData = inspector.get_pk_constraint(tableName, schema=schema)
    pkCols = list(pkData.get("constrained_columns") or [])
    fkData = inspector.get_foreign_keys(tableName, schema=schema) or []

    # Build ColumnInfo list
    colInfos: List[ColumnInfo] = []
    pkSet = set(pkCols)
    fkColsSet = set()
    for fk in fkData:
        fkColsSet.update(fk.get("constrained_columns") or [])

    for c in colsData:
        typeName = str(c.get("type"))
        default = None
        if "default" in c and c["default"] is not None:
            default = str(c["default"])
        colInfos.append(
            ColumnInfo(
                name=c["name"],
                typeName=typeName,
                isPrimaryKey=c["name"] in pkSet,
                isForeignKey=c["name"] in fkColsSet,
                isNullable=bool(c.get("nullable", True)),
                default=default,
            )
        )

    # Build ForeignKeyInfo list
    fkInfos: List[ForeignKeyInfo] = []
    for fk in fkData:
        fkInfos.append(
            ForeignKeyInfo(
                name=fk.get("name"),
                sourceTable=tableName,
                sourceSchema=schema,
                sourceColumns=fk.get("constrained_columns") or [],
                targetTable=fk.get("referred_table"),
                targetSchema=fk.get("referred_schema"),
                targetColumns=fk.get("referred_columns") or [],
            )
        )

    return TableInfo(
        name=tableName,
        schema=schema,
        columns=colInfos,
        primaryKeyCols=pkCols,
        foreignKeys=fkInfos,
    )

def reflectDatabase(inspector: Inspector, includeSchemas: Optional[List[str]], excludeSchemas: Optional[List[str]]) -> List[TableInfo]:
    tables: List[TableInfo] = []
    for schema in listSchemas(inspector, includeSchemas, excludeSchemas):
        for tableName in inspector.get_table_names(schema=schema):
            tables.append(reflectTable(inspector, schema, tableName))
        # Optionally include views:
        for viewName in inspector.get_view_names(schema=schema):
            tables.append(reflectTable(inspector, schema, viewName))
    return tables


# -------- Graph Building ------------------------------------------------------

def htmlEscape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
    )

def tableDisplayName(schema: Optional[str], name: str, showSchema: bool) -> str:
    return f"{schema}.{name}" if (showSchema and schema) else name

def buildNodeLabel(table: TableInfo, showSchemaInHeader: bool) -> str:
    """
    Build an HTML-like Graphviz label with a header (table name) and rows for each column.
    PK columns are marked with 🔑, FK columns with 🔗, nullability, and type are shown.
    """
    header = htmlEscape(tableDisplayName(table.schema, table.name, showSchemaInHeader))
    rows = []
    # Sort: PKs first, then others
    def colSortKey(c: ColumnInfo) -> Tuple[int, str]:
        return (0 if c.isPrimaryKey else 1, c.name.lower())

    for c in sorted(table.columns, key=colSortKey):
        flags = []
        if c.isPrimaryKey:
            flags.append("🔑")
        if c.isForeignKey:
            flags.append("🔗")
        if not c.isNullable:
            flags.append("NOT NULL")
        flagStr = " ".join(flags)
        typeStr = htmlEscape(c.typeName)
        defaultStr = f" = {htmlEscape(c.default)}" if c.default else ""
        rows.append(
            f"<TR><TD ALIGN='LEFT'><B>{htmlEscape(c.name)}</B></TD>"
            f"<TD ALIGN='LEFT'>{typeStr}{defaultStr}</TD>"
            f"<TD ALIGN='LEFT'>{htmlEscape(flagStr)}</TD></TR>"
        )

    label = f"""<
<TABLE BORDER="1" CELLBORDER="0" CELLPADDING="4">
  <TR><TD BGCOLOR="lightgrey" ALIGN="LEFT" COLSPAN="3"><B>{header}</B></TD></TR>
  <TR><TD ALIGN="LEFT"><I>column</I></TD><TD ALIGN="LEFT"><I>type / default</I></TD><TD ALIGN="LEFT"><I>flags</I></TD></TR>
  {''.join(rows)}
</TABLE>
>"""
    return label

def buildGraph(tables: List[TableInfo], showSchemaInHeader: bool, rankdir: str = "LR") -> Digraph:
    g = Digraph("ERD", format="png")
    g.attr(rankdir=rankdir)
    g.attr("node", shape="plain", fontsize="10")
    
    # Improved graph layout for even spacing
    g.attr(splines="polyline")      # Polyline edges for clean look with labels
    g.attr(nodesep="1.8")          # Increased horizontal space between nodes  
    g.attr(ranksep="2.0")          # Increased vertical space between ranks
    g.attr(concentrate="false")     # Don't merge parallel edges
    g.attr(overlap="false")        # Prevent node overlap
    g.attr(pack="false")           # Don't pack tightly - allow even distribution
    g.attr(sep="+40")              # Overall separation increase
    g.attr(esep="+20")             # Edge separation
    g.attr(layout="dot")           # Use dot layout engine for hierarchical layout
    g.attr(ordering="out")         # Order edges coming out of nodes

    # Create nodes
    nodeIds: Dict[Tuple[Optional[str], str], str] = {}
    for idx, t in enumerate(tables):
        nodeId = f"node_{idx}"
        nodeIds[(t.schema, t.name)] = nodeId
        g.node(nodeId, label=buildNodeLabel(t, showSchemaInHeader))

    # Create edges for FKs
    for t in tables:
        for fk in t.foreignKeys:
            sourceId = nodeIds.get((fk.sourceSchema, fk.sourceTable))
            targetId = nodeIds.get((fk.targetSchema, fk.targetTable))
            if not sourceId or not targetId:
                # target could be in excluded schema; skip
                continue

            # Build a readable edge label mapping columns
            pairs = []
            for i, srcCol in enumerate(fk.sourceColumns):
                tgtCol = fk.targetColumns[i] if i < len(fk.targetColumns) else "(?)"
                pairs.append(f"{srcCol} → {fk.targetTable}.{tgtCol}")
            edgeLabel = "\\n".join(pairs)
            if fk.name:
                edgeLabel = f"{fk.name}\\n{edgeLabel}"

            g.edge(sourceId, targetId, label=edgeLabel, arrowsize="0.7", 
                   penwidth="1.2", color="gray40", fontsize="8")

    return g


# -------- CLI ---------------------------------------------------------------

def parseArgs() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate ERD for a PostgreSQL database or SQL file.")
    
    # Input source - either database URL or SQL file (mutually exclusive)
    input_group = p.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--db", "--database-url", dest="dbUrl",
                            help="SQLAlchemy URL, e.g., postgresql+psycopg2://user:pass@host:5432/dbname")
    input_group.add_argument("--sql", "--sql-file", dest="sqlFile",
                            help="Path to SQL file containing CREATE TABLE statements")
    
    # Output options
    p.add_argument("--out", dest="outPath", default="erd.svg", help="Output file path (default: erd.svg)")
    p.add_argument("--format", dest="outFormat", default="svg", choices=["svg", "png", "pdf"],
                   help="Output format for Graphviz render (default: svg)")
    
    # Schema filtering (only applicable for database input)
    p.add_argument("--include-schemas", nargs="*", default=None,
                   help="Schemas to include (database input only, default: all except pg_catalog, information_schema)")
    p.add_argument("--exclude-schemas", nargs="*", default=None,
                   help="Schemas to exclude (database input only, in addition to defaults)")
    
    # Graph options
    p.add_argument("--rankdir", default="LR", choices=["LR", "TB", "BT", "RL"],
                   help="Graph layout direction (Left-Right, Top-Bottom, etc.)")
    p.add_argument("--show-schema-in-headers", action="store_true",
                   help="Prefix table headers with schema name.")
    p.add_argument("--debug", action="store_true",
                   help="Print parsed table information instead of generating ERD")
    
    return p.parse_args()

def main():
    args = parseArgs()
    
    # Get table information from either database or SQL file
    if args.dbUrl:
        # Database input
        inspector = getInspector(args.dbUrl)
        tables = reflectDatabase(
            inspector,
            includeSchemas=args.include_schemas,
            excludeSchemas=args.exclude_schemas
        )
    elif args.sqlFile:
        # SQL file input
        try:
            tables = parseSqlFile(args.sqlFile)
        except FileNotFoundError:
            raise SystemExit(f"Error: SQL file not found: {args.sqlFile}")
        except Exception as e:
            raise SystemExit(f"Error parsing SQL file: {e}")
        
        # Schema filtering not applicable for SQL files, but warn if specified
        if args.include_schemas or args.exclude_schemas:
            print("Warning: Schema filtering options are ignored when using SQL file input.")
    else:
        raise SystemExit("Error: Must specify either --db or --sql")

    if not tables:
        if args.dbUrl:
            raise SystemExit("No tables/views found with the given schema filters.")
        else:
            raise SystemExit("No CREATE TABLE statements found in the SQL file.")

    # Debug mode: print table information instead of generating ERD
    if args.debug:
        print(f"Found {len(tables)} tables:")
        for table in tables:
            print(f"\nTable: {table.schema}.{table.name}")
            print(f"  Primary Keys: {', '.join(table.primaryKeyCols)}")
            print(f"  Columns:")
            for col in table.columns:
                flags = []
                if col.isPrimaryKey:
                    flags.append("PK")
                if col.isForeignKey:
                    flags.append("FK")
                if not col.isNullable:
                    flags.append("NOT NULL")
                flag_str = f" [{', '.join(flags)}]" if flags else ""
                default_str = f" DEFAULT {col.default}" if col.default else ""
                print(f"    {col.name}: {col.typeName}{default_str}{flag_str}")
            print(f"  Foreign Keys:")
            for fk in table.foreignKeys:
                print(f"    {', '.join(fk.sourceColumns)} -> {fk.targetSchema}.{fk.targetTable}({', '.join(fk.targetColumns)})")
        return

    graph = buildGraph(
        tables,
        showSchemaInHeader=args.show_schema_in_headers,
        rankdir=args.rankdir
    )

    # Respect desired format and file name
    graph.format = args.outFormat
    try:
        outFile = graph.render(filename=args.outPath, cleanup=True)
        print(f"ERD written to: {outFile}")
    except Exception as e:
        if "Graphviz executables" in str(e):
            print("Error: Graphviz is not installed or not in PATH.")
            print("Please install Graphviz from https://graphviz.org/download/")
            print("Alternative: Use --debug flag to see parsed table structure without generating ERD.")
        else:
            print(f"Error generating ERD: {e}")
        raise SystemExit(1)

if __name__ == "__main__":
    main()
