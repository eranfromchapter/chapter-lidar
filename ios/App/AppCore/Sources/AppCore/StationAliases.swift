// StationClient and PackageKit (PackageCore) both mirror the station's upload schemas with the same
// type names (UploadSession, FileStatus, PackageStatus, UploadTarget, ...), and the module
// `StationClient` also has a type named `StationClient`, so `StationClient.UploadSession` cannot
// be written. This file imports only StationClient and gives its types unambiguous names; the
// bridge (StationUploadService.swift) imports only PackageCore and uses these aliases.
import StationClient

public typealias StationAPI = StationClient
public typealias StationAPIError = StationError
public typealias StationAPIProblem = Problem
public typealias StationAPIUploadSessionRequest = UploadSessionRequest
public typealias StationAPIUploadFileDeclaration = UploadFileDeclaration
public typealias StationAPIUploadSession = UploadSession
public typealias StationAPIUploadSessionFile = UploadSessionFile
public typealias StationAPIUploadTarget = UploadTarget
public typealias StationAPIFileStatus = FileStatus
public typealias StationAPIPackageStatus = PackageStatus
public typealias StationAPIFileCheckResult = FileCheckResult
public typealias StationAPIPackage = Package
public typealias StationAPIPackageFile = PackageFile
public typealias StationAPIVerdictSummary = VerdictSummary
public typealias StationAPIHubProject = HubProject
public typealias StationAPIProjectStore = ProjectStore
public typealias StationAPITokenProvider = AccessTokenProvider
public typealias StationAPITransport = HTTPTransport
