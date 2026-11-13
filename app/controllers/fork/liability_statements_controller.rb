# Statements for a card or loan: what Plaid reported, and manual entry for what
# it did not (design §4.5, R9.5, R9.6).
class Fork::LiabilityStatementsController < ApplicationController
  include AccountAuthorizable

  before_action :set_account
  before_action :set_statement, only: %i[edit update destroy]
  before_action :require_write, only: %i[new create edit update destroy]

  def index
    @statements = @account.fork_liability_statements.newest_first.includes(:recurring_occurrence)
  end

  def new
    @statement = @account.fork_liability_statements.new(currency: @account.currency, due_on: Date.current)
  end

  def create
    @statement = Fork::Liabilities::Recorder.record_manual(@account, statement_params, funding_account: funding_account)
    return render_invalid unless @statement&.persisted?

    redirect_to account_liability_statements_path(@account), notice: t(".created")
  rescue ActiveRecord::RecordInvalid => e
    @statement = e.record
    render_invalid
  end

  def edit
  end

  def update
    updated = Fork::Liabilities::Recorder.record_manual(
      @account, statement_params, funding_account: funding_account, statement: @statement
    )
    return render_invalid("edit") unless updated

    redirect_to account_liability_statements_path(@account), notice: t(".updated")
  rescue ActiveRecord::RecordInvalid => e
    @statement = e.record
    render_invalid("edit")
  end

  def destroy
    @statement.destroy!
    redirect_to account_liability_statements_path(@account), notice: t(".destroyed")
  end

  private
    def set_account
      @account = accessible_accounts.find(params[:account_id])
      raise ActiveRecord::RecordNotFound unless @account.credit_card? || @account.loan?
    end

    def set_statement
      @statement = @account.fork_liability_statements.find(params[:id])
    end

    def require_write
      require_account_permission!(@account, redirect_path: account_liability_statements_path(@account))
    end

    def render_invalid(template = "new")
      @statement ||= @account.fork_liability_statements.new
      flash.now[:alert] = t("fork.liability_statements.form.invalid")
      render template, status: :unprocessable_entity
    end

    def statement_params
      params.require(:fork_liability_statement).permit(
        :issued_on, :due_on, :statement_balance, :minimum_due, :last_payment_amount, :last_payment_on, :is_overdue
      )
    end

    # A member's choice of funding account, limited to accounts they can write.
    def funding_account
      id = params.dig(:fork_liability_statement, :funding_account_id).presence
      id && Account.writable_by(Current.user).where(family_id: Current.family.id).where.not(id: @account.id).find_by(id: id)
    end
end
