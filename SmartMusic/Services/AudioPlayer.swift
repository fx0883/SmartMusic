import Foundation
import AVFoundation
import SwiftData
import MediaPlayer  // 添加这一行

class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    private var player: AVPlayer?
    private let logger = LogService.shared
    
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentSong: Song?
    
    private var timeObserver: Any?
    private var modelContext: ModelContext?
    
    private init() {
        setupRemoteTransportControls()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func play(_ song: Song) {
        guard let url = URL(string: song.url) else {
            logger.error("Invalid song URL: \(song.url)")
            return
        }
        
        logger.info("Starting to play song: \(song.title)")
        
        if currentSong?.id == song.id {
            logger.debug("Resuming current song")
            player?.play()
            isPlaying = true
            return
        }
        
        currentSong = song
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // 观察播放时间
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        // 观察音频时长
        player?.currentItem?.asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            DispatchQueue.main.async {
                self.duration = playerItem.asset.duration.seconds
            }
        }
        
        player?.play()
        isPlaying = true
        setupNowPlaying(song: song)
        
        // 添加到播放历史
        addToHistory(song)
        
        logger.info("Successfully started playing: \(song.title)")
    }
    
    private func addToHistory(_ song: Song) {
        guard let modelContext = modelContext else {
            logger.error("ModelContext not set")
            return
        }
        
        Task { @MainActor in
            do {
                let descriptor = FetchDescriptor<PlayHistory>(
                    predicate: #Predicate<PlayHistory> { $0.song.id == song.id }
                )
                
                if let existingHistory = try? modelContext.fetch(descriptor).first {
                    existingHistory.playCount += 1
                    existingHistory.lastPlayedAt = Date()
                } else {
                    let history = PlayHistory(song: song)
                    modelContext.insert(history)
                }
                
                try? modelContext.save()
                logger.info("Added song to history: \(song.title)")
            } catch {
                logger.error("Failed to save history: \(error.localizedDescription)")
            }
        }
    }
    
    func pause() {
        logger.debug("Pausing playback")
        player?.pause()
        isPlaying = false
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            player?.play()
            isPlaying = true
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1)
        player?.seek(to: cmTime)
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.isPlaying = true
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            return .success
        }
    }
    
    private func setupNowPlaying(song: Song) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist
        
        if let url = URL(string: song.albumCover) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }.resume()
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}