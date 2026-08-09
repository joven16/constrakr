//
//  CachedThumbnailImage.swift
//  ConsTrakr
//

import SwiftUI
import UIKit

struct CachedThumbnailImage<Placeholder: View>: View {
    let cacheKey: String
    let maxPixelSize: Int
    let loader: @Sendable () -> Data?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            if let cached = PhotoThumbnailCache.cachedImage(forKey: cacheKey) {
                image = cached
                return
            }
            image = await PhotoThumbnailCache.loadImage(
                forKey: cacheKey,
                maxPixelSize: maxPixelSize,
                loader: loader
            )
        }
    }
}

struct PunchThumbnailView: View {
    let attendanceId: UUID
    var size: CGFloat = 36

    var body: some View {
        CachedThumbnailImage(
            cacheKey: "attendance-\(attendanceId.uuidString)-\(Int(size))",
            maxPixelSize: Int(size * 3),
            loader: { AttendancePhotoStore.load(attendanceId: attendanceId) }
        ) {
            Color.clear
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct EmployeeAvatarView: View {
    let employee: Employee
    var size: CGFloat = 50

    var body: some View {
        CachedThumbnailImage(
            cacheKey: "enrollment-\(employee.id.uuidString)-center-\(Int(size))",
            maxPixelSize: Int(size * 3),
            loader: { EnrollmentPhotoStore.load(employeeId: employee.id, pose: .center) }
        ) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                Text(initials)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color(.systemGray))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let first = employee.firstName.prefix(1)
        let last = employee.lastName.prefix(1)
        return "\(first)\(last)".uppercased()
    }
}
