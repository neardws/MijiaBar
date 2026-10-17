import MijiaCore

/// 第一次用到才创建（会读钥匙串里的登录信息）
@MainActor enum Lazy { static let controller = Controller(cloud: Session.load().map { XiaomiCloud(session: $0) }) }
@MainActor var controller: Controller { Lazy.controller }
