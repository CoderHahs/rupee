# Links to the source of the running version, which AGPLv3 section 13 asks
# for when anyone other than the operator uses the app (design §7.7).
module Fork::SourceHelper
  def fork_source_url
    Rails.configuration.x.source_url
  end

  # The running commit's tree, or the repository when the commit is unknown.
  def fork_source_commit_url(sha = Sure.commit_sha)
    sha.present? ? "#{fork_source_url}/tree/#{sha}" : fork_source_url
  end
end
