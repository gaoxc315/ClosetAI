import SwiftUI

struct ContentView: View {
    @StateObject private var wardrobeVM = WardrobeViewModel()
    @StateObject private var outfitVM = OutfitViewModel()
    @StateObject private var categoryStore = CategoryStore()

    var body: some View {
        TabView {
            WardrobeView()
                .tabItem {
                    Label("衣橱", systemImage: "hanger")
                }
                .environmentObject(wardrobeVM)
                .environmentObject(outfitVM)
                .environmentObject(categoryStore)

            OutfitView()
                .tabItem {
                    Label("穿搭", systemImage: "wand.and.stars")
                }
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)
                .environmentObject(categoryStore)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
                .environmentObject(wardrobeVM)
                .environmentObject(categoryStore)
        }
        .accentColor(AppColors.accent)
    }
}
