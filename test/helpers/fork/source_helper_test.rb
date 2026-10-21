require "test_helper"

class Fork::SourceHelperTest < ActionView::TestCase
  test "links to the running commit's tree in the fork's repository" do
    assert_equal "https://github.com/CoderHahs/rupee/tree/abc123", fork_source_commit_url("abc123")
  end

  test "links to the repository when the commit is unknown" do
    assert_equal "https://github.com/CoderHahs/rupee", fork_source_commit_url(nil)
  end
end
