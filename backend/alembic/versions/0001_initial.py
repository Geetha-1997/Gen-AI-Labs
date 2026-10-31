"""Initial users, conversations and messages."""
from alembic import op
import sqlalchemy as sa
revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table("users", sa.Column("id",sa.Integer(),primary_key=True),sa.Column("email",sa.String(320),nullable=False),sa.Column("password_hash",sa.String(255),nullable=False),sa.Column("is_active",sa.Boolean(),nullable=False,server_default=sa.true()),sa.Column("created_at",sa.DateTime(timezone=True),nullable=False))
    op.create_index("ix_users_email","users",["email"],unique=True)
    op.create_table("conversations",sa.Column("id",sa.Integer(),primary_key=True),sa.Column("user_id",sa.Integer(),sa.ForeignKey("users.id",ondelete="CASCADE"),nullable=False),sa.Column("title",sa.String(200),nullable=False),sa.Column("created_at",sa.DateTime(timezone=True),nullable=False),sa.Column("updated_at",sa.DateTime(timezone=True),nullable=False))
    op.create_index("ix_conversations_user_id","conversations",["user_id"])
    op.create_table("messages",sa.Column("id",sa.Integer(),primary_key=True),sa.Column("conversation_id",sa.Integer(),sa.ForeignKey("conversations.id",ondelete="CASCADE"),nullable=False),sa.Column("role",sa.String(20),nullable=False),sa.Column("content",sa.Text(),nullable=False),sa.Column("created_at",sa.DateTime(timezone=True),nullable=False))
    op.create_index("ix_messages_conversation_id","messages",["conversation_id"])

def downgrade():
    op.drop_index("ix_messages_conversation_id",table_name="messages"); op.drop_table("messages")
    op.drop_index("ix_conversations_user_id",table_name="conversations"); op.drop_table("conversations")
    op.drop_index("ix_users_email",table_name="users"); op.drop_table("users")
