import UIKit

extension UIApplication {
    /// Resigns whatever currently holds the keyboard. `.searchable` has no focus control before iOS 18,
    /// so this is the way to put the keyboard away when something else takes over the screen.
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
