import Testing
import Foundation
import UIKit
import CoreGraphics
@testable import NomLens

// MARK: - M1: CharacterCrop

struct CharacterCropTests {

    @Test func defaultsDecodedCharacterToNil() {
        let crop = CharacterCrop(
            id: UUID(),
            image: UIImage(),
            boundingBox: .zero,
            observationIndex: 0,
            characterIndex: 0,
            normalizedBox: .zero
        )
        #expect(crop.decodedCharacter == nil)
        #expect(crop.transliteration == nil)
        #expect(crop.confidence == nil)
        #expect(crop.isAmbiguous == false)
        #expect(crop.decodeResult == nil)
    }

    @Test func identifiableIdIsStable() {
        let id = UUID()
        let crop = CharacterCrop(
            id: id,
            image: UIImage(),
            boundingBox: .zero,
            observationIndex: 0,
            characterIndex: 0,
            normalizedBox: .zero
        )
        #expect(crop.id == id)
    }
}

// MARK: - M1: PreprocessingSettings presets

struct PreprocessingSettingsTests {

    @Test func stelePresetHasAdaptiveThresholdEnabled() {
        #expect(PreprocessingSettings.stele.adaptiveThresholdEnabled == true)
    }

    @Test func stelePresetHasHighContrast() {
        #expect(PreprocessingSettings.stele.contrast >= 1.8)
    }

    @Test func manuscriptPresetHasAdaptiveThresholdDisabled() {
        #expect(PreprocessingSettings.manuscript.adaptiveThresholdEnabled == false)
    }

    @Test func manuscriptPresetHasPositiveBrightness() {
        #expect(PreprocessingSettings.manuscript.brightness > 0)
    }

    @Test func cleanPrintPresetDisablesNoiseReduction() {
        #expect(PreprocessingSettings.cleanPrint.noiseReductionEnabled == false)
    }

    @Test func cleanPrintPresetDisablesSharpening() {
        #expect(PreprocessingSettings.cleanPrint.sharpenEnabled == false)
    }

    @Test func defaultSettingsHaveSensibleRanges() {
        let s = PreprocessingSettings()
        #expect(s.contrast >= 0.5 && s.contrast <= 4.0)
        #expect(s.brightness >= -1.0 && s.brightness <= 1.0)
        #expect(s.noiseLevel >= 0.0 && s.noiseLevel <= 0.1)
        #expect(s.sharpenRadius >= 0.0 && s.sharpenRadius <= 100.0)
        #expect(s.sharpenIntensity >= 0.0 && s.sharpenIntensity <= 1.0)
    }
}

// MARK: - M1: PerspectiveQuad

struct PerspectiveQuadTests {

    @Test func identityQuadCornersAreAtExpectedPositions() {
        let q = PerspectiveQuad.identity
        #expect(q.topLeft == CGPoint(x: 0, y: 1))
        #expect(q.topRight == CGPoint(x: 1, y: 1))
        #expect(q.bottomLeft == CGPoint(x: 0, y: 0))
        #expect(q.bottomRight == CGPoint(x: 1, y: 0))
    }
}

// MARK: - M1: API key loading

struct APIKeyTests {

    @Test func apiKeyIsLoadedFromBundle() {
        let key = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        // If this fails: verify Config.xcconfig is assigned to Debug + Release configurations
        // and that the Info tab on the NomLens target has CLAUDE_API_KEY = $(CLAUDE_API_KEY).
        #expect(key != nil)
        #expect(key?.isEmpty == false)
    }
}

// MARK: - M1: CharacterDecodeResult JSON decoding

struct CharacterDecodeResultTests {

    @Test func decodesFullResponseCorrectly() throws {
        let json = """
        {
          "character": "南",
          "type": "han",
          "quoc_ngu": "nam",
          "meaning": "south",
          "confidence": "high",
          "alternate_readings": [],
          "damage_noted": false,
          "notes": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(CharacterDecodeResult.self, from: data)

        #expect(result.character == "南")
        #expect(result.type == .han)
        #expect(result.quocNgu == "nam")
        #expect(result.meaning == "south")
        #expect(result.confidence == .high)
        #expect(result.alternateReadings.isEmpty)
        #expect(result.damageNoted == false)
        #expect(result.notes == nil)
    }

    @Test func decodesNullCharacterResponseCorrectly() throws {
        let json = """
        {
          "character": null,
          "type": null,
          "quoc_ngu": null,
          "meaning": null,
          "confidence": "none",
          "alternate_readings": [],
          "damage_noted": true,
          "notes": "too damaged to identify"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(CharacterDecodeResult.self, from: data)

        #expect(result.character == nil)
        #expect(result.confidence == .none)
        #expect(result.damageNoted == true)
        #expect(result.notes == "too damaged to identify")
    }

    @Test func decodesAlternateReadings() throws {
        let json = """
        {
          "character": "𡨸",
          "type": "nom",
          "quoc_ngu": "chữ",
          "meaning": "character / script",
          "confidence": "medium",
          "alternate_readings": ["tự", "chú"],
          "damage_noted": false,
          "notes": "ambiguous glyph form"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(CharacterDecodeResult.self, from: data)

        #expect(result.alternateReadings.count == 2)
        #expect(result.alternateReadings.contains("tự"))
        #expect(result.alternateReadings.contains("chú"))
    }
}
