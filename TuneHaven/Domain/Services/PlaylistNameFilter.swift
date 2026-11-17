import Foundation

/// 歌单首页「搜索你的歌单」：只按名称筛选本机自建歌单，规则与音乐库搜索一致（原文、拼音、首字母）。
/// 不搜索歌单内歌曲，也不联网（交互设计文档 §4.2）。
enum PlaylistNameFilter {
    static func filter(_ playlists: [Playlist], query: String) -> [Playlist] {
        guard let prepared = PinyinSearchMatcher.prepare(query) else { return playlists }
        return playlists.filter { !$0.isSystem && PinyinSearchMatcher.matches(text: $0.name, query: prepared) }
    }
}
