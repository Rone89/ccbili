import Foundation

struct VideoDetailResponseDTO: Decodable {
    let bvid: String?
    let aid: Int?
    let cid: Int?
    let title: String?
    let desc: String?
    let pubdate: Int?
    let ctime: Int?
    let owner: VideoDetailOwnerDTO?
    let pages: [VideoDetailPageDTO]?
    let stat: VideoDetailStatDTO?
    let reqUser: VideoDetailReqUserDTO?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, cid, title, desc, pubdate, ctime, owner, pages, stat
        case reqUser = "req_user"
    }
}

struct VideoDetailStatDTO: Decodable {
    let view: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?
    let share: Int?
}

struct VideoDetailReqUserDTO: Decodable {
    let attention: Int?
    let favorite: Int?
    let like: Int?
    let coin: Int?
}

struct VideoDetailOwnerDTO: Decodable {
    let name: String?
    let mid: Int?
    let face: String?
}

struct VideoDetailPageDTO: Decodable {
    let cid: Int?
    let page: Int?
    let part: String?
}

struct RelatedVideoDTO: Decodable {
    let bvid: String?
    let aid: Int?
    let cid: Int?
    let title: String?
    let pic: String?
    let owner: RelatedVideoOwnerDTO?
}

struct RelatedVideoOwnerDTO: Decodable {
    let name: String?
}

struct UserCardResponseDTO: Decodable {
    let code: Int
    let message: String
    let data: UserCardDataDTO?
}

struct UserCardDataDTO: Decodable {
    let card: UserCardDTO?
    let follower: Int?
}

struct UserCardDTO: Decodable {
    let mid: String?
    let name: String?
    let face: String?
}
