import SwiftUI
// import Amplify
// import AWSCognitoAuthPlugin
// import AWSAPIPlugin
// import AWSS3StoragePlugin

@main
struct My_LifestyleApp: App {
    init() {
        // Once your Amplify Gen 2 sandbox is deployed and amplify_outputs.json
        // is added to the project, uncomment this block to connect the app
        // to your backend:
        //
        // do {
        //     try Amplify.add(plugin: AWSCognitoAuthPlugin())
        //     try Amplify.add(plugin: AWSAPIPlugin())
        //     try Amplify.add(plugin: AWSS3StoragePlugin())
        //     try Amplify.configure()
        // } catch {
        //     print("Unable to configure Amplify: \(error)")
        // }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
