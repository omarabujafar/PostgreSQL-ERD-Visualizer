# PostgreSQL Visualizer

A Python script that generates Entity Relationship Diagrams (ERDs) for PostgreSQL databases using SQLAlchemy reflection and Graphviz rendering.

## Features

- **Dual Input Modes**: Connect directly to PostgreSQL databases OR parse SQL DDL files
- **Multiple Output Formats**: SVG, PNG, PDF
- **Clean Visual Design**: Professional ERD layouts with primary keys, foreign keys, and data types
- **Flexible Layout Options**: Top-to-bottom, left-to-right, and other orientations
- **Schema Management**: Include/exclude specific schemas
- **Smart Parsing**: Handles complex PostgreSQL syntax including enums, constraints, and relationships

## Installation

### Prerequisites

1. **Python 3.7+**
2. **Graphviz**: Must be installed on your system and accessible via PATH
   - Download from [https://graphviz.org/download/](https://graphviz.org/download/)
   - On Windows: Make sure to add Graphviz `bin` directory to your system PATH

### Python Dependencies

```bash
pip install sqlalchemy psycopg2 graphviz
```

**Note**: For SQL file mode only, you only need the `graphviz` package. The `sqlalchemy` and `psycopg2` packages are only required for database connection mode.

## Usage

### SQL File Mode (Recommended)

Generate ERD from SQL DDL file:

```bash
python "PostgreSQL Visualizer.py" --sql schema.sql --out diagram.svg
```

```bash
# Generate PDF with top-to-bottom layout
python "PostgreSQL Visualizer.py" --sql schema.sql --out diagram.pdf --format pdf --rankdir TB

# Generate PNG
python "PostgreSQL Visualizer.py" --sql schema.sql --out diagram.png --format png
```

### Database Connection Mode

Connect directly to a PostgreSQL database:

```bash
python "PostgreSQL Visualizer.py" --db "postgresql+psycopg2://user:pass@localhost:5432/mydb" --out erd.svg
```

```bash
# Include specific schemas
python "PostgreSQL Visualizer.py" --db "postgresql+psycopg2://user:pass@host:5432/db" --include-schemas public myschema --out diagram.pdf --format pdf
```

### Additional Options

```bash
# Show schema names in table headers
python "PostgreSQL Visualizer.py" --sql schema.sql --show-schema-in-headers --out diagram.svg

# Debug mode: show parsed structure without generating ERD
python "PostgreSQL Visualizer.py" --sql schema.sql --debug

# Change layout direction (TB = top-to-bottom, LR = left-to-right)
python "PostgreSQL Visualizer.py" --sql schema.sql --rankdir TB --out diagram.svg
```

## Command Line Arguments

| Argument | Description | Example |
|----------|-------------|---------|
| `--sql` | SQL file path | `--sql schema.sql` |
| `--db` | Database connection URL | `--db "postgresql+psycopg2://user:pass@host/db"` |
| `--out` | Output file path | `--out diagram.pdf` |
| `--format` | Output format (svg, png, pdf) | `--format pdf` |
| `--rankdir` | Layout direction (TB, LR, BT, RL) | `--rankdir TB` |
| `--include-schemas` | Include specific schemas (database mode) | `--include-schemas public app` |
| `--exclude-schemas` | Exclude specific schemas | `--exclude-schemas temp audit` |
| `--show-schema-in-headers` | Show schema names in table headers | `--show-schema-in-headers` |
| `--debug` | Show parsed structure without generating ERD | `--debug` |

## SQL Parsing Capabilities

The tool can parse complex PostgreSQL DDL including:

- ✅ CREATE TABLE statements with various column types
- ✅ PRIMARY KEY constraints (table-level and column-level)
- ✅ FOREIGN KEY constraints with proper relationship mapping
- ✅ ENUM types and custom data types
- ✅ NOT NULL, DEFAULT values, and CHECK constraints
- ✅ Multi-column primary and foreign keys
- ✅ Nested parentheses in column definitions
- ✅ SQL comments (automatically removed)

## Troubleshooting

### Graphviz Not Found Error

If you get "Graphviz is not installed or not in PATH":

1. **Windows**: Download Graphviz from the official website and ensure the `bin` directory is in your system PATH
2. **Alternative**: Use the provided `run_visualizer.bat` script which automatically sets the PATH
3. **Debug Mode**: Use `--debug` flag to test SQL parsing without requiring Graphviz

### Large Schema Performance

For very large databases:
- Use `--include-schemas` to limit scope
- Consider excluding system schemas with `--exclude-schemas`
- Try different `--rankdir` options for better layout

## Output Examples

The tool generates professional ERDs showing:
- 🔑 Primary keys with key icons
- 🔗 Foreign key relationships with arrows
- 📊 Data types and constraints
- 🏗️ Clean, organized table layouts

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please feel free to submit issues and pull requests.