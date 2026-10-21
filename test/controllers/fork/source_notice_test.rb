require "test_helper"

# The AGPLv3 source offer on pages with the shared footer (design §7.7).
class Fork::SourceNoticeTest < ActionDispatch::IntegrationTest
  test "the sign-in page links to the source of the running commit" do
    Sure.stubs(:commit_sha).returns("0123456789abcdef")

    get new_session_url

    assert_response :success
    assert_select "footer a[href='https://github.com/CoderHahs/rupee/tree/0123456789abcdef']",
                  text: I18n.t("fork.source_notice.commit_link", commit: "0123456")
  end
end
