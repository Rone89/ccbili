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
