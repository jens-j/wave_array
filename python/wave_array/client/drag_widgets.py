from PyQt5.QtCore             import Qt, QMimeData
from PyQt5.QtGui              import QDrag, QPixmap
from PyQt5.QtWidgets          import QLabel, QListWidget

import pyqtgraph              as pg


# QListWidget sublass that can formats QDrag events with table name.
class DragListWidget(QListWidget):

    def mouseMoveEvent(self, e):       

        if e.buttons() == Qt.LeftButton:

            drag = QDrag(self)

            # Add table name as mime data to the QDrag item.
            mime = QMimeData()
            mime.setText(self.currentItem().text())
            drag.setMimeData(mime)

            # Craate drag visual.
            label = QLabel(self.currentItem().text())
            pixmap = QPixmap(label.size())
            label.render(pixmap)
            drag.setPixmap(pixmap)

            drag.exec_(Qt.MoveAction)


# Pyqtgraph PlotWidget sublass that can handle drops.
class DropPlotWidget(pg.PlotWidget):

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)

    def dragEnterEvent(self, e):
        e.accept()

    def dragLeaveEvent(self, e):
        e.accept()

    def dragMoveEvent(self, e):
        e.accept()

    def dropEvent(self, e):
        index = self.parent().layout().indexOf(self) - 1 # Skip table list.
        print(f'{index} <= {e.mimeData().text()}')
        e.accept()
