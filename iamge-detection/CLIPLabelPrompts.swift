//
//  CLIPLabelPrompts.swift
//  iamge-detection
//
//  Zero-shot prompt ensemble for 3 fixed categories.
//  Each image is ONE phone screenshot — a single frozen frame with visible caption,
//  hashtags, username, and UI chrome. Prompts describe static visual cues, not video playback.
//
//  Boundary rules:
//  - Creator in frame → educational if caption teaches; entertainment if caption is comedy; commercial if caption sells
//  - Finance topic     → educational if caption explains; commercial if caption promotes a product or offer
//  - Branded post      → educational if publisher explainer; commercial if ad or marketing infographic
//

import Foundation

enum CLIPLabelPrompts {
    /// Bump when prompts change so text-embedding cache refreshes.
    static let version = 6

    static func prompts(for label: String) -> [String] {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "educational content": return educationalPrompts
        case "commercial content":  return commercialPrompts
        case "entertainment content": return entertainmentPrompts
        default: return []
        }
    }

    // Visible in screenshot: explainer caption, lesson text, verified publisher, how-to hashtags

    private static let educationalPrompts = [
        "a phone screenshot of tiktok showing a caption about learning, explaining, or how something works",
        "a phone screenshot with on-screen text teaching a skill, concept, method, or step by step lesson",
        "a phone screenshot of a creator with a caption about goal setting, productivity, study tips, or habits",
        "a phone screenshot showing a talking head frame with an instructional caption about a framework or strategy",
        "a phone screenshot of a verified news or media account with an explainer caption about economics or science",
        "a phone screenshot with hashtags like LearnOnTikTok, explained, or tips in the visible caption area",
        "a phone screenshot of documentary or explainer style content with informative caption text at the bottom",
        "a phone screenshot where the visible caption and on-screen text aim to teach and inform the viewer",
    ]

    // Visible in screenshot: sponsored label, buy/sign up caption, promotional infographic, brand offer

    private static let commercialPrompts = [
        "a phone screenshot of a tiktok ad with sponsored label or a caption urging buy now or sign up",
        "a phone screenshot with a call to action in the caption like link in bio, shop now, or subscribe",
        "a phone screenshot of influencer content with a caption advertising a paid course, app, or product",
        "a phone screenshot of a branded promotional infographic selling wealth, investment, or business offers",
        "a phone screenshot with discount, limited time offer, or persuasive sales text in the caption",
        "a phone screenshot where the visible caption and on-screen text persuade the viewer to purchase something",
        "a phone screenshot of a sponsored brand post promoting financial services or products for sale",
        "a phone screenshot where the caption and layout clearly advertise and drive a purchase decision",
    ]

    // Visible in screenshot: comedy caption, meme layout, dance pose, no lesson or sales text

    private static let entertainmentPrompts = [
        "a phone screenshot of a funny tiktok with a comedy caption or humorous on-screen text",
        "a phone screenshot of a viral meme or absurd humor post on social media",
        "a phone screenshot showing a dance pose, lip sync, or music trend with no instructional caption",
        "a phone screenshot of a gaming highlight or sports moment shared for amusement",
        "a phone screenshot of a reaction or fail moment with a caption meant to make the viewer laugh",
        "a phone screenshot of celebrity gossip, fan edit, or pop culture content for enjoyment",
        "a phone screenshot where the visible caption is purely humorous with no lesson and no sales pitch",
        "a phone screenshot of fun leisure content with comedy or amusement as the only visible purpose",
    ]
}
