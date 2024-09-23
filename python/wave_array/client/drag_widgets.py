from PyQt5.QtCore             import Qt, QMimeData
from PyQt5.QtGui              import QDrag, QPixmap, QPainter
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
        self.callback = None
        self.setAcceptDrops(True)

    # Re-implement paint to draw border around plot.
    def paintEvent(self, event):
        super().paintEvent(event)
        with QPainter(self.viewport()) as painter:
            painter.setPen(pg.mkPen(color=(255, 255, 255)))
            painter.drawRect(self.boundingRect().adjusted(1,1,-1,-1))
            # print(self.boundingRect().adjusted(1,1,-1,-1))
        

    def dragEnterEvent(self, e):
        e.accept()

    def dragLeaveEvent(self, e):
        e.accept()

    def dragMoveEvent(self, e):
        e.accept()

    def addDropCallback(self, callback):
        self.callback = callback

    def dropEvent(self, e):
        index = self.parent().layout().indexOf(self) # Skip table list.
        table_name = e.mimeData().text()
        e.accept()
        self.callback(table_name, index)
