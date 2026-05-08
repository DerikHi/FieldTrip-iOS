# FieldTrip iOS

An iOS app for discovering and reviewing outdoor facilities and natural spaces. Search for locations, submit insights with ratings, and explore results on a map.

## Features

- **Authentication** — Email/password registration, login, password reset, and email verification via Firebase Auth
- **Search** — Find locations by city name, coordinates, or current location with list and map views
- **Insights** — Submit reviews with facility ratings and comments for discovered locations

## Requirements

- Xcode 16+
- iOS 18+
- A Firebase project with Authentication enabled

## Setup

1. Clone the repository
2. Open `FieldTrip.xcodeproj` in Xcode
3. Add the [Firebase Apple SDK](https://github.com/firebase/firebase-ios-sdk) via **File > Add Package Dependencies** — select **FirebaseCore** and **FirebaseAuth**
4. Add your `GoogleService-Info.plist` to the project
5. Build and run

## Project Structure

```
FieldTrip/
├── App/                    # App entry point and root navigation
├── Authentication/
│   ├── Models/             # User model
│   ├── Services/           # Auth, Keychain, and Validation services
│   ├── ViewModels/         # Login, Registration, Forgot Password
│   └── Views/              # Login, Registration, Email Verification
├── Features/
│   ├── Insights/           # Location review and rating submission
│   └── Search/             # Location search with list and map views
└── Assets.xcassets
```
