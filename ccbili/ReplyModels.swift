import Foundation

struct ReplyListResponse: Decodable {
    let code: Int
    let message: String
    let data: ReplyListData?
}

struct ReplyListData: Decodable {
    let replies: [ReplyItemDTO]?
}

struct ReplyItemDTO: Decodable {
    let rpid: Int?
    let ctime: Int?
    let content: ReplyContentDTO?
    let member: ReplyMemberDTO?
    let like: Int?
    let rcount: Int?
    let replies: [ReplyItemDTO]?
}

struct ReplyContentDTO: Decodable {
    let message: String?
}

struct ReplyMemberDTO: Decodable {
    let uname: String?
    let mid: String?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case uname
        case mid
        case avatar
    }
}
