@echo off
set "PATH=%PATH%;C:\Program Files\Graphviz\bin"
python "PostgreSQL Visualizer.py" --sql test_schema.sql --out "ERD Logic" --format pdf --rankdir TB