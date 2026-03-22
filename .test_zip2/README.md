# Execution

Questa directory contiene gli script Python deterministici che eseguono il lavoro effettivo.

## Convenzioni

- Ogni script legge le variabili d'ambiente dal file `.env` nella root del progetto
- Usa `python-dotenv` per caricare le variabili: `from dotenv import load_dotenv`
- Input/output chiari e documentati nel docstring dello script
- Gestione degli errori con messaggi espliciti
