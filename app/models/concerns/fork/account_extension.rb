# Fork additions to Account, applied in config/initializers/fork.rb so
# account.rb stays unedited (design §4.1).
module Fork::AccountExtension
  extend ActiveSupport::Concern

  included do
    has_many :fork_liability_statements, class_name: "Fork::LiabilityStatement", dependent: :destroy
  end
end
