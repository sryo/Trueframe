// Animates session photos at end of capture.

import UIKit

protocol TumbleAnimationDelegate: AnyObject {
    func tumbleAnimationDidComplete()
}

final class TumbleAnimationViewController: UIViewController {
    weak var delegate: TumbleAnimationDelegate?
    private var photoViews: [UIImageView] = []
    private let photos: [UIImage]

    init(photos: [UIImage]) {
        self.photos = photos
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAnimation()
    }

    private func startAnimation() {
        guard !photos.isEmpty else {
            delegate?.tumbleAnimationDidComplete()
            return
        }

        createPhotoViews()
        fallIntoStack()

        // Quick cascade: 0.4s fall + 0.6s explode = 1s total
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.explodePhotos()
        }

        // Immediate transition after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.delegate?.tumbleAnimationDidComplete()
        }
    }

    private func createPhotoViews() {
        let maxPhotos = min(photos.count, 10)
        let photoSize: CGFloat = 110
        let center = view.center

        for index in 0..<maxPhotos {
            let imageView = UIImageView(image: photos[index])
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8
            imageView.layer.borderWidth = 2
            imageView.layer.borderColor = UIColor.white.cgColor
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0.4
            imageView.layer.shadowOffset = CGSize(width: 0, height: 4)
            imageView.layer.shadowRadius = 8

            let stackOffsetX = CGFloat.random(in: -12...12)
            let stackOffsetY = CGFloat.random(in: -12...12)
            let stackRotation = CGFloat.random(in: -0.12...0.12)

            imageView.frame = CGRect(
                x: center.x - photoSize / 2 + stackOffsetX,
                y: center.y - photoSize / 2 + stackOffsetY,
                width: photoSize,
                height: photoSize
            )

            imageView.alpha = 0
            imageView.transform = CGAffineTransform(scaleX: 1.8, y: 1.8).rotated(by: stackRotation)

            view.addSubview(imageView)
            photoViews.append(imageView)
        }
    }

    private func fallIntoStack() {
        for (index, imageView) in photoViews.enumerated() {
            let delay = Double(index) * 0.025
            let currentRotation = atan2(imageView.transform.b, imageView.transform.a)

            UIView.animate(withDuration: 0.25, delay: delay, options: .curveEaseOut) {
                imageView.alpha = 1
                imageView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0).rotated(by: currentRotation)
            }
        }
    }

    private func explodePhotos() {
        let center = view.center
        let radius = max(view.bounds.width, view.bounds.height)

        for (index, imageView) in photoViews.enumerated() {
            let baseAngle = (CGFloat(index) / CGFloat(photoViews.count)) * 2 * .pi
            let angle = baseAngle + CGFloat.random(in: -0.4...0.4)
            let distance = radius * CGFloat.random(in: 0.8...1.1)

            let targetX = center.x + cos(angle) * distance
            let targetY = center.y + sin(angle) * distance
            let targetRotation = CGFloat.random(in: -4...4)
            let delay = Double(index) * 0.01

            UIView.animate(
                withDuration: 0.45,
                delay: delay,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.5
            ) {
                imageView.center = CGPoint(x: targetX, y: targetY)
                imageView.transform = CGAffineTransform(rotationAngle: targetRotation).scaledBy(x: 0.4, y: 0.4)
                imageView.alpha = 0
            }
        }
    }
}
