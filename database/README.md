# Database operations

Production database: Amazon RDS for PostgreSQL, provisioned by `infra/terraform`. The application schema migrations remain in `backend/alembic` and are run by the deployment bootstrap before the API starts. Do not maintain a second copy of Alembic migrations here.

## Backup policy

- Terraform enables encrypted RDS storage, Multi-AZ, and 7-day automated backups.
- Use RDS point-in-time recovery for operational restore.
- Create a manual snapshot before risky schema changes.
- Test restore into a separate instance/VPC before relying on a backup.
- Never commit `.sql`, `.dump`, `.bak`, credentials, or real customer data.

For local development, Compose uses the named `postgres_data` volume. Do not run `docker compose down -v` unless you intend to permanently delete that local database volume.
