//
//  ClipDropDelegate.swift
//  Framwise
//
//  Clip grid drag-and-drop reorder delegate
//

import SwiftUI

// MARK: - Clip Drop Delegate

struct ClipDropDelegate: DropDelegate {
    let targetClipID: UUID
    @Binding var draggedClipID: UUID?
    @Binding var dropTargetID: UUID?
    let onMove: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedClipID != nil && draggedClipID != targetClipID
    }

    func dropEntered(info: DropInfo) {
        dropTargetID = targetClipID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetClipID {
            dropTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggedClipID else { return false }
        onMove(draggedID, targetClipID)
        draggedClipID = nil
        dropTargetID = nil
        return true
    }
}
