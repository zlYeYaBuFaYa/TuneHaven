import Testing
import Foundation
@testable import TuneHaven

// MARK: - 第三轮测试修复回归

// MARK: - #1 播放队列按传入顺序排列（需求3）

@Suite("PlayQueue Order Preservation Tests")
struct PlayQueueOrderTests {

    @Test("replaceQueue 保持传入歌曲的顺序", .serialized)
    @MainActor
    func testReplaceQueuePreservesOrder() {
        let service = PlayQueueService()
        let songs = ["Charlie", "Alpha", "Bravo"].map { makeSong(title: $0) }
        service.replaceQueue(with: songs, startAt: 0)

        #expect(service.queue[0].song.title == "Charlie")
        #expect(service.queue[1].song.title == "Alpha")
        #expect(service.queue[2].song.title == "Bravo")
    }

    @Test("replaceQueue startAt 设置为中间位置时 currentIndex 正确", .serialized)
    @MainActor
    func testReplaceQueueStartAtMiddle() {
        let service = PlayQueueService()
        let songs = ["A", "B", "C", "D", "E"].map { makeSong(title: $0) }
        service.replaceQueue(with: songs, startAt: 2)

        #expect(service.currentIndex == 2)
        #expect(service.currentItem?.song.title == "C")
        #expect(service.queue.count == 5)
    }

    @Test("按收藏时间排序的歌曲列表构建队列后顺序一致", .serialized)
    @MainActor
    func testQueueFromFavoriteSortedList() {
        let service = PlayQueueService()
        let songs = ["最新收藏", "中间收藏", "最早收藏"].map { makeSong(title: $0) }

        let targetSong = songs[1]
        let startIndex = songs.firstIndex(where: { $0.id == targetSong.id }) ?? 0
        service.replaceQueue(with: songs, startAt: startIndex)

        #expect(service.currentIndex == 1)
        #expect(service.currentItem?.song.title == "中间收藏")
        #expect(service.queue[0].song.title == "最新收藏")
        #expect(service.queue[2].song.title == "最早收藏")
    }
}

// MARK: - #2 ThemeManager setTheme 正常工作（需求2）

@Suite("ThemeManager SetTheme Tests")
struct ThemeManagerSetThemeTests {

    @Test("setTheme 切换到暮光玫瑰后 currentStyle 更新")
    @MainActor
    func testSetThemeUpdatesCurrentStyle() {
        let manager = ThemeManager()
        manager.applyTier(.premium)
        manager.setTheme(.twilightRose)

        #expect(manager.currentStyle.id == "twilight_rose")
        #expect(manager.palette.background == ThemeStyle.twilightRose.palette.background)
    }

    @Test("setTheme 从星际穹顶切换到暮光玫瑰后 colorScheme 保持 dark")
    @MainActor
    func testSetThemeCosmicToTwilight() {
        let manager = ThemeManager()
        manager.applyTier(.premium)
        manager.setTheme(.cosmicTech)
        #expect(manager.colorScheme == .dark)

        manager.setTheme(.twilightRose)
        #expect(manager.colorScheme == .dark)
        #expect(manager.currentStyle.id == "twilight_rose")
    }

    @Test("setTheme 从深色主题切换到浅色主题 colorScheme 变为 light")
    @MainActor
    func testSetThemeDarkToLight() {
        let manager = ThemeManager()
        manager.applyTier(.premium)
        manager.setTheme(.cosmicTech)
        #expect(manager.colorScheme == .dark)

        manager.setTheme(.cloudWhite)
        #expect(manager.colorScheme == .light)
    }

    @Test("连续多次 setTheme 最终状态正确")
    @MainActor
    func testMultipleSetTheme() {
        let manager = ThemeManager()
        manager.applyTier(.premium)
        manager.setTheme(.azureSky)
        manager.setTheme(.cosmicTech)
        manager.setTheme(.twilightRose)
        manager.setTheme(.cloudWhite)

        #expect(manager.currentStyle.id == "cloud_white")
        #expect(manager.colorScheme == .light)
    }
}

// MARK: - #3 收藏切换逻辑（需求4）

@Suite("Favorite Toggle Logic Tests")
struct FavoriteToggleTests {

    @Test("makeSong 默认 isFavorite 为 false")
    func testDefaultNotFavorite() {
        let song = makeSong(title: "Test")
        #expect(song.isFavorite == false)
        #expect(song.favoriteDate == nil)
    }

    @Test("从收藏列表移除歌曲后列表更新")
    func testRemoveFromFavoritesList() {
        var favorites = ["A", "B", "C"].map { makeSong(title: $0) }
        let songToRemove = favorites[1]

        favorites.removeAll { $0.id == songToRemove.id }

        #expect(favorites.count == 2)
        #expect(favorites[0].title == "A")
        #expect(favorites[1].title == "C")
    }
}
