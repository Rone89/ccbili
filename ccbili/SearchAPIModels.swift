import Foundation

struct SearchAllResponseDTO: Decodable {
    let code: Int
    let message: String
    let data: SearchAllDataDTO?
}

struct SearchAllDataDTO: Decodable {
    let result: [SearchResultItemDTO]?
}

struct SearchVideoResponseDTO: Decodable {
    let code: Int
    let message: String
    let data: SearchVideoDataDTO?
}

struct SearchVideoDataDTO: Decodable {
    let result: [SearchResultItemDTO]?
    let numPages: Int?
    let page: Int?

    enum CodingKeys: String, CodingKey {
        case result
        case numPages = "numPages"
        case page
    }
}

struct SearchUserResponseDTO: Decodable {
    let code: Int
    let message: String
    let data: SearchUserDataDTO?
}

struct SearchUserDataDTO: Decodable {
    let result: [SearchUserItemDTO]?
    let numPages: Int?
    let page: Int?

    enum CodingKeys: String, CodingKey {
        case result
        case numPages
        case page
    }
}

struct SearchUserItemDTO: Decodable {
    let mid: Int?
    let uname: String?
    let usign: String?
    let fans: Int?
    let videos: Int?
    let upic: String?
}

struct SearchResultItemDTO: Decodable {
    let bvid: String?
    let aid: Int?
    let title: String?
    let author: String?
    let pic: String?
    let description: String?
    let duration: String?

    enum CodingKeys: String, CodingKey {
        case bvid
        case aid
        case title
        case author
        case pic
        case description
        case duration
    }
}

struct SearchUserItem: Identifiable, Hashable {
    let id: String
    let mid: Int
    let name: String
    let sign: String
    let followerText: String
    let videoText: String
    let avatarURL: URL?
}

struct UserProfile: Hashable {
    let mid: Int
    let name: String
    let sign: String
    let followerText: String
    let followingText: String
    let videoText: String
    let avatarURL: URL?
}

struct UserArchiveResponseDTO: Decodable {
    let code: Int
    let message: String
    let data: UserArchiveDataDTO?
}

struct UserArchiveDataDTO: Decodable {
    let list: UserArchiveListDTO?
    let page: UserArchivePageDTO?
}

struct UserArchiveListDTO: Decodable {
    let vlist: [UserArchiveVideoDTO]?
}

struct UserArchivePageDTO: Decodable {
    let pn: Int?
    let ps: Int?
    let count: Int?
}

struct UserArchiveVideoDTO: Decodable {
    let bvid: String?
    let aid: Int?
    let title: String?
    let pic: String?
    let length: String?
    let created: Int?
}
