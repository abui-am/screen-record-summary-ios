//
//  ClassificationCategory.swift
//  iamge-detection
//
//  3 categories. Image prompts score screenshots; audio prompts score tone + transcript.
//

import Foundation

struct ClassificationCategory: Sendable, Equatable {
    let name: String
    let prompts: [String]
}

enum ClassificationCategories {
    static let all: [ClassificationCategory] = [
        ClassificationCategory(name: "Educational content", prompts: educationalPrompts),
        ClassificationCategory(name: "Commercial content", prompts: commercialPrompts),
        ClassificationCategory(name: "Entertainment content", prompts: entertainmentPrompts),
    ]

    static let audioAll: [ClassificationCategory] = [
        ClassificationCategory(name: "Educational content", prompts: audioEducationalPrompts),
        ClassificationCategory(name: "Commercial content", prompts: audioCommercialPrompts),
        ClassificationCategory(name: "Entertainment content", prompts: audioEntertainmentPrompts),
    ]

    static var allPrompts: [String] {
        all.flatMap(\.prompts)
    }

    static var audioPrompts: [String] {
        audioAll.flatMap(\.prompts)
    }

    static var categoryNames: [String] {
        all.map(\.name)
    }

    static func category(containing prompt: String) -> ClassificationCategory? {
        all.first { $0.prompts.contains(prompt) }
            ?? audioAll.first { $0.prompts.contains(prompt) }
    }

    // Teach · explain · inform · faith · motivation · coaching

    private static let educationalPrompts = [
        "a phone screenshot of a person talking to camera against a clean plain background on tiktok",
        "a phone screenshot showing an individual speaking directly to the viewer with a minimal uncluttered backdrop",
        "a phone screenshot of a creator at a desk or studio with a clean background explaining or teaching something",
        "a phone screenshot showing a talking head with an instructional caption about a framework, strategy, or idea",
        "a phone screenshot of a man or woman in casual clothes talking directly to camera about business, success, or money",
        "a phone screenshot of short-form vertical video with one person speaking about investing, entrepreneurship, or career growth",
        "a phone screenshot of a creator explaining how to grow on YouTube, TikTok, or social media",
        "a phone screenshot of a motivational speaker or life coach talking to camera with an inspiring caption",
        "a phone screenshot of business or career coaching content with advice about skills, mindset, or growth",
        "a phone screenshot of self-improvement or personal development content with a serious talking head",
        "a phone screenshot of a creator giving motivational advice or professional coaching on social media",
        "a phone screenshot of religious or faith-based content teaching scripture, prayer, or spiritual guidance",
        "a phone screenshot of a creator explaining a lesson through a story or parable in the caption",
        "a phone screenshot with on-screen text or caption about faith, religion, bible, quran, or spiritual teaching",
    ]

    // Sell · promote · convert — must show explicit ad/CTA/sponsored signals, not just any caption

    private static let commercialPrompts = [
        "a phone screenshot of a tiktok with a sponsored label or paid advertisement badge visible",
        "a phone screenshot with buy now, shop now, link in bio, or sign up in the visible caption",
        "a phone screenshot of influencer content with a caption advertising a paid course, app, or product for sale",
        "a phone screenshot of a branded promotional infographic selling wealth, investment, or business offers",
        "a phone screenshot with discount code, limited time offer, or sale price in the caption",
        "a phone screenshot of a tiktok shop product listing or shoppable ad in the feed",
        "a phone screenshot of a sponsored brand post promoting financial services or consumer products for sale",
        "a phone screenshot with explicit sales call to action text urging the viewer to purchase or subscribe",
    ]

    // Brainrot · memes · absurd humor — owns surreal viral clips, gaming memes, nonsense tiktoks

    private static let entertainmentPrompts = [
        "a phone screenshot of brainrot or absurd surreal meme tiktok with weird nonsensical humor",
        "a phone screenshot of cursed internet humor or chaotic viral clip shared purely for entertainment",
        "a phone screenshot of a roblox, minecraft, or gaming meme video shared for laughs not learning",
        "a phone screenshot of a bizarre or nonsensical tiktok meme with no product ad and no lesson",
        "a phone screenshot showing someone performing a choreographed dance or lip sync to trending music without speaking",
        "a phone screenshot of a prank, fail, or slapstick moment with a caption meant to make the viewer laugh",
        "a phone screenshot of a comedy skit or joke caption with no teaching intent and no sales pitch",
        "a phone screenshot of absurd viral humor content where nothing is being sold or taught",
    ]

    private static let audioEducationalPrompts = [
        "spoken audio of someone explaining a lesson, teaching a concept, or giving instructional advice",
        "a voice talking about faith, scripture, prayer, or spiritual guidance",
        "someone narrating a tutorial, how-to, or educational story",
        "speech describing a framework, strategy, or idea meant to inform the listener",
        "spoken advice about investing money, building a business, or entrepreneurship",
        "speech explaining how to succeed on YouTube, grow an audience, or crack a content formula",
        "someone talking about becoming successful through consistent effort, skills, or mindset",
        "motivational or inspirational speech about skills, mindset, personal growth, or self-improvement",
        "coaching advice about career development, undervalued skills, or professional growth",
        "energetic passionate speech meant to motivate, teach, or inspire the listener not to sell a product",
        "calm measured explanatory speech with normal conversational delivery",
    ]

    private static let audioCommercialPrompts = [
        "spoken audio advertising a product, course, app, or paid offer for sale",
        "a sales pitch with buy now, shop now, link in bio, or sign up language",
        "promotional speech about discounts, limited time offers, or sponsored products",
        "voice-over urging the listener to purchase, subscribe, or invest money",
        "fast urgent energetic sales delivery with explicit buy now or sign up language",
    ]

    private static let audioEntertainmentPrompts = [
        "meme sound effects, trending audio, or chaotic viral clip audio meant for laughs",
        "song lyrics or sung vocals from a trending tiktok or reel audio track",
        "a viral meme phrase, catchphrase, or quoted line from entertainment media",
        "music-heavy entertainment audio with no teaching or sales intent",
        "absurd or nonsensical spoken humor with no product pitch",
        "gaming meme audio, lip sync trend audio, or comedy skit dialogue",
        "short expletive or profanity outburst in a viral clip not meant to teach",
    ]
}
