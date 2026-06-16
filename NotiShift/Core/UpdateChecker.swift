import Foundation

struct ReleaseInfo {
  let version: String
  let url: URL
  let notes: String?
}

enum UpdateCheckResult {
  case upToDate(currentVersion: String)
  case updateAvailable(currentVersion: String, release: ReleaseInfo)
}

enum UpdateCheckError: LocalizedError {
  case missingCurrentVersion
  case invalidReleaseResponse
  case invalidReleaseURL
  case invalidVersion(current: String, latest: String)

  var errorDescription: String? {
    switch self {
    case .missingCurrentVersion:
      return L10n.text("update.errorMissingCurrentVersion")
    case .invalidReleaseResponse:
      return L10n.text("update.errorInvalidReleaseResponse")
    case .invalidReleaseURL:
      return L10n.text("update.errorInvalidReleaseURL")
    case let .invalidVersion(current, latest):
      return String(format: L10n.text("update.errorInvalidVersion"), current, latest)
    }
  }
}

final class UpdateChecker {
  private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case htmlURL = "html_url"
      case body
      case draft
      case prerelease
    }
  }

  private let releaseURL: URL
  private let session: URLSession

  init(releaseURL: URL = AppConstants.latestReleaseURL, session: URLSession = .shared) {
    self.releaseURL = releaseURL
    self.session = session
  }

  func check() async throws -> UpdateCheckResult {
    guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      throw UpdateCheckError.missingCurrentVersion
    }

    var request = URLRequest(url: releaseURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("NotiShift", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard
      let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw UpdateCheckError.invalidReleaseResponse
    }

    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
    guard !release.draft, !release.prerelease else {
      throw UpdateCheckError.invalidReleaseResponse
    }
    guard let releasePageURL = URL(string: release.htmlURL) else {
      throw UpdateCheckError.invalidReleaseURL
    }
    guard
      let current = AppVersion(currentVersion),
      let latest = AppVersion(release.tagName)
    else {
      throw UpdateCheckError.invalidVersion(current: currentVersion, latest: release.tagName)
    }

    if latest > current {
      return .updateAvailable(
        currentVersion: currentVersion,
        release: ReleaseInfo(version: release.tagName, url: releasePageURL, notes: release.body)
      )
    }

    return .upToDate(currentVersion: currentVersion)
  }
}
