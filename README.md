# TemplateCam - Auto Template Camera MVP

A professional iOS camera app that uses Vision-based pose detection and automatic lens selection to help photographers match reference photo compositions.

## Features

- **Template-Based Photography**: Import a reference photo to generate a composition template
- **Vision Pose Detection**: Real-time human body pose detection using Apple's Vision framework
- **Auto Lens Selection**: Automatically switches between ultrawide/wide/telephoto lenses based on subject framing
- **Live Coaching**: On-screen guidance to help match the template ("Step Forward", "Step Back", etc.)
- **Manual Controls**: Fine-tune exposure, white balance, contrast, saturation, and more
- **Haptic Feedback**: Subtle vibration when alignment is perfect
- **Preview Parity**: What you see is what you get - preview matches final photo processing

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Physical iOS device with camera (simulator not supported for camera features)

## Project Structure

```
TemplateCam/
├── AppDelegate.swift              # App lifecycle
├── SceneDelegate.swift            # Scene management
├── Info.plist                     # App configuration & permissions
├── Resources/
│   ├── Assets.xcassets           # App assets
│   └── Templates/
│       └── seed_template.json    # Default template
├── Camera/                        # Core camera modules
│   ├── CaptureSession.swift      # AVFoundation camera management
│   ├── LensPicker.swift           # Auto lens selection logic
│   ├── ExposureWB.swift           # Exposure & white balance control
│   ├── PhotoPipeline.swift        # Core Image processing
│   ├── Template.swift             # Template data model
│   ├── TemplateStore.swift        # Template persistence
│   ├── TemplateGenerator.swift    # Generate templates from photos
│   ├── OverlayRenderer.swift      # Draw template overlays
│   ├── MatchScorer.swift          # Score framing & pose match
│   └── CoachingHUD.swift          # User coaching interface
├── UI/                            # View controllers
│   ├── CameraViewController.swift           # Main camera UI
│   ├── TemplateControlsView.swift          # Manual adjustment controls
│   └── ImportTemplateViewController.swift   # Template import flow
└── Utils/                         # Utilities
    ├── Haptics.swift              # Haptic feedback wrapper
    └── Logging.swift              # Debug logging

Tests/
├── TemplateTests.swift            # Template model tests
└── LensPickerTests.swift          # Lens selection tests
```

## Build & Run

### 1. Clone the Repository

```bash
git clone <repository-url>
cd templatecam
```

### 2. Open in Xcode

```bash
open TemplateCam/TemplateCam.xcodeproj
```

### 3. Configure Signing

1. Select the **TemplateCam** target in Xcode
2. Go to **Signing & Capabilities**
3. Select your development team
4. Ensure automatic signing is enabled

### 4. Connect iOS Device

- Connect your iPhone or iPad via USB
- Select your device from the device menu in Xcode
- Trust the device if prompted

### 5. Build and Run

- Press **⌘R** or click the **Run** button
- Grant camera and photo library permissions when prompted

## Usage

### Basic Camera Operation

1. **Launch App**: The camera view opens with a default template overlay
2. **View Overlay**: Green box shows target subject framing, white lines show pose skeleton
3. **Coaching**: Follow on-screen instructions ("Step Forward", "Rotate Left", etc.)
4. **Capture**: Tap the white circular button to take a photo
5. **Manual Adjustments**: Tap the slider icon (top-left) to adjust exposure, contrast, etc.

### Import Custom Template

1. Tap the **photo icon** (bottom-left)
2. Select a reference photo containing a single person
3. Wait for Vision processing to generate the template
4. The new template automatically becomes active with overlays

### Lens Switching

- **Auto Mode**: App automatically selects the best lens based on subject distance
- **Manual Override**: Tap the lens button (bottom-right) to cycle through available lenses
- Displays: 0.5x (ultrawide), 1x (wide), 2x (telephoto)

### Flash Control

- Tap the **bolt icon** (top-right) to cycle: Off → Auto → On

## Key Technical Details

### Auto Lens Selection

The app uses a **probe-and-pick** strategy:

1. Measures subject height at zoom=1.0 for each available lens
2. Calculates `zoomNeeded = targetHeight / liveHeight`
3. Selects lens where `zoomNeeded` is closest to 1.0 (minimizes digital zoom)
4. Debounces lens switches (minimum 1.5s between changes)

### Template Data Model (v1)

Templates are stored as JSON with the following structure:

```json
{
  "id": "template_001",
  "v": 1,
  "subject": {
    "bbox": { "x": 0.28, "y": 0.12, "w": 0.44, "h": 0.68 },
    "targetBoxHeightPct": 0.68,
    "keybones": [["left_shoulder", "right_shoulder"], ...]
  },
  "cameraTargets": {
    "tone": {
      "exposureEV": 0.0,
      "contrast": 1.0,
      "highlights": 0.0,
      "shadows": 0.0,
      "saturation": 1.0,
      "vibrance": 0.0,
      "sharpness": 0.0
    },
    "wb": { "temperature": 5500, "tint": 0 }
  }
}
```

### Photo Processing Pipeline

1. **Exposure Adjust** (CIExposureAdjust)
2. **Vibrance** (CIVibrance)
3. **Saturation & Contrast** (CIColorControls)
4. **Highlights/Shadows** (CIToneCurve with 5 anchors)
5. **Sharpness** (CIUnsharpMask)

The same pipeline processes both preview frames and captured photos for perfect parity.

### Coaching Algorithm

Scores are calculated based on:

- **Framing Score** (60%): Subject height match within 8% tolerance
- **Pose Score** (40%): Keybone angle similarity

Overall score ≥ 0.85 triggers "Perfect!" message and haptic feedback.

## Known Limitations

1. **Single Subject Only**: Template generation requires exactly one person in frame
2. **No Face/Hand Tracking**: Only tracks torso and legs (shoulders, hips, knees)
3. **Lens Availability**: Works best on iPhone 13 Pro or later (3 lenses); degrades gracefully on older models
4. **Horizon Detection**: Simplified algorithm; works best with clear horizontal edges
5. **White Balance Locking**: Some devices may not support full temperature/tint range
6. **Processing Time**: Template generation takes 2-5 seconds depending on image size
7. **Lighting Conditions**: Pose detection accuracy decreases in low light
8. **No ARKit**: Currently doesn't use ARKit for 3D pose estimation

## Testing

### Run Unit Tests

```bash
# From command line
xcodebuild test -project TemplateCam.xcodeproj -scheme TemplateCam -destination 'platform=iOS Simulator,name=iPhone 15'

# Or in Xcode: ⌘U
```

### Test Coverage

- **TemplateTests**: Template model validation, JSON encoding/decoding, value clamping
- **LensPickerTests**: Lens selection logic, zoom calculation, debouncing

## Troubleshooting

### Camera Not Starting

- Ensure camera permissions are granted in Settings → TemplateCam
- Check that you're running on a physical device (not simulator)
- Verify iOS version is 16.0 or later

### No Pose Overlay Visible

- Ensure good lighting conditions
- Stand 2-5 meters from camera
- Face the camera with full body visible
- Check that subject is centered in frame

### Lens Switching Not Working

- Some devices only have 1-2 lenses (this is normal)
- Debouncing prevents rapid switches (wait 1.5s)
- Check logs for "Lens switch" messages

### Template Generation Fails

- Ensure photo contains exactly one person
- Subject should be clearly visible (not obscured)
- Good lighting and contrast help Vision accuracy

## Architecture Notes

### UIKit + AVCaptureVideoPreviewLayer

Uses UIKit (not SwiftUI) for camera preview to provide:

- Direct control over AVCaptureVideoPreviewLayer
- Precise CAShapeLayer overlay positioning
- Better performance for real-time video processing

### Vision Framework Integration

- Runs `VNDetectHumanBodyPoseRequest` every 5 frames
- Extracts 6 key joints: shoulders, hips, knees
- Confidence threshold: 0.3 for overlay, 0.5 for scoring

### Core Image Pipeline

- Uses Metal-backed CIContext for GPU acceleration
- Reuses filter instances to minimize allocation
- Renders directly to CVPixelBuffer for preview efficiency

## License

This project is provided as an MVP demonstration. All code uses public Apple APIs only.

## Credits

Built with:
- AVFoundation (camera & media)
- Vision (pose detection)
- Core Image (image processing)
- UIKit (user interface)