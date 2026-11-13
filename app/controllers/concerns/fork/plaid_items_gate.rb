# Prepended to PlaidItemsController (design §4.2).
#
# `new` is guarded by the Item budget: at the cap it renders the budget
# explanation instead of opening Link (R2.5). `edit` is update mode, creates
# no Item and is never guarded (R2.6). `create` is not guarded either: by then
# Link has finished and the Item exists at Plaid.
module Fork::PlaidItemsGate
  def new
    return render_budget_exhausted if Fork::PlaidItemBudget.blocked?

    super
  end

  def edit
    # Choosing to add accounts answers the "new accounts available" prompt.
    @plaid_item.update!(new_accounts_available_at: nil) if params[:add_accounts] == "true" && @plaid_item.new_accounts_available_at
    super
  end

  private
    def render_budget_exhausted
      @used = Fork::PlaidItemBudget.used
      @cap = Fork::PlaidItemBudget.cap
      render "fork/plaid_item_budgets/exhausted", layout: false
    end
end
