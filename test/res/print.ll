@fmt.i32 = constant [3 x i8] c"%d "
declare i32 @printf(i8* noalias nocapture, ...)
declare i8* @malloc(i64)
declare void @free(i8*)
define i64 @main() {
  %fun.1809 = bitcast i8* ()* @state.1110 to i8*
  %cast.1810 = bitcast i8* %fun.1809 to i8* ()*
  %arg.1571 = call i8* %cast.1810()
  %cursor.1812 = bitcast i8* (i8*, i8*)* @lam.1570 to i8*
  %sizeptr.1828 = getelementptr i64, i64* null, i32 0
  %size.1829 = ptrtoint i64* %sizeptr.1828 to i64
  %cursor.1813 = call i8* @malloc(i64 %size.1829)
  %cast.1819 = bitcast i8* %cursor.1813 to {}*
  %sizeptr.1830 = getelementptr i64, i64* null, i32 2
  %size.1831 = ptrtoint i64* %sizeptr.1830 to i64
  %ans.1811 = call i8* @malloc(i64 %size.1831)
  %cast.1814 = bitcast i8* %ans.1811 to {i8*, i8*}*
  %loader.1817 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1814, i32 0, i32 0
  store i8* %cursor.1812, i8** %loader.1817
  %loader.1815 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1814, i32 0, i32 1
  store i8* %cursor.1813, i8** %loader.1815
  %fun.1572 = bitcast i8* %ans.1811 to i8*
  %base.1820 = bitcast i8* %fun.1572 to i8*
  %castedBase.1821 = bitcast i8* %base.1820 to {i8*, i8*}*
  %loader.1827 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1821, i32 0, i32 0
  %down.elim.cls.1573 = load i8*, i8** %loader.1827
  %loader.1826 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1821, i32 0, i32 1
  %down.elim.env.1574 = load i8*, i8** %loader.1826
  %fun.1822 = bitcast i8* %down.elim.cls.1573 to i8*
  %arg.1823 = bitcast i8* %arg.1571 to i8*
  %arg.1824 = bitcast i8* %down.elim.env.1574 to i8*
  %cast.1825 = bitcast i8* %fun.1822 to i8* (i8*, i8*)*
  %tmp.1832 = tail call i8* %cast.1825(i8* %arg.1823, i8* %arg.1824)
  %cast.1833 = ptrtoint i8* %tmp.1832 to i64
  ret i64 %cast.1833
}
define i8* @lam.1503(i8* %A.1112, i8* %env.1502) {
  %base.1805 = bitcast i8* %env.1502 to i8*
  %castedBase.1806 = bitcast i8* %base.1805 to {}*
  %sizeptr.1834 = getelementptr i64, i64* null, i32 0
  %size.1835 = ptrtoint i64* %sizeptr.1834 to i64
  %ans.1807 = call i8* @malloc(i64 %size.1835)
  %cast.1808 = bitcast i8* %ans.1807 to {}*
  ret i8* %ans.1807
}
define i8* @lam.1505(i8* %S.1111, i8* %env.1504) {
  %base.1794 = bitcast i8* %env.1504 to i8*
  %castedBase.1795 = bitcast i8* %base.1794 to {}*
  %cursor.1797 = bitcast i8* (i8*, i8*)* @lam.1503 to i8*
  %sizeptr.1836 = getelementptr i64, i64* null, i32 0
  %size.1837 = ptrtoint i64* %sizeptr.1836 to i64
  %cursor.1798 = call i8* @malloc(i64 %size.1837)
  %cast.1804 = bitcast i8* %cursor.1798 to {}*
  %sizeptr.1838 = getelementptr i64, i64* null, i32 2
  %size.1839 = ptrtoint i64* %sizeptr.1838 to i64
  %ans.1796 = call i8* @malloc(i64 %size.1839)
  %cast.1799 = bitcast i8* %ans.1796 to {i8*, i8*}*
  %loader.1802 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1799, i32 0, i32 0
  store i8* %cursor.1797, i8** %loader.1802
  %loader.1800 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1799, i32 0, i32 1
  store i8* %cursor.1798, i8** %loader.1800
  ret i8* %ans.1796
}
define i8* @state.1110() {
  %cursor.1786 = bitcast i8* (i8*, i8*)* @lam.1505 to i8*
  %sizeptr.1840 = getelementptr i64, i64* null, i32 0
  %size.1841 = ptrtoint i64* %sizeptr.1840 to i64
  %cursor.1787 = call i8* @malloc(i64 %size.1841)
  %cast.1793 = bitcast i8* %cursor.1787 to {}*
  %sizeptr.1842 = getelementptr i64, i64* null, i32 2
  %size.1843 = ptrtoint i64* %sizeptr.1842 to i64
  %ans.1785 = call i8* @malloc(i64 %size.1843)
  %cast.1788 = bitcast i8* %ans.1785 to {i8*, i8*}*
  %loader.1791 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1788, i32 0, i32 0
  store i8* %cursor.1786, i8** %loader.1791
  %loader.1789 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1788, i32 0, i32 1
  store i8* %cursor.1787, i8** %loader.1789
  ret i8* %ans.1785
}
define i8* @io.1136(i8* %state.1116) {
  %sizeptr.1844 = getelementptr i64, i64* null, i32 0
  %size.1845 = ptrtoint i64* %sizeptr.1844 to i64
  %ans.1774 = call i8* @malloc(i64 %size.1845)
  %cast.1775 = bitcast i8* %ans.1774 to {}*
  %arg.1506 = bitcast i8* %ans.1774 to i8*
  %ans.1776 = bitcast i8* %state.1116 to i8*
  %fun.1507 = bitcast i8* %ans.1776 to i8*
  %base.1777 = bitcast i8* %fun.1507 to i8*
  %castedBase.1778 = bitcast i8* %base.1777 to {i8*, i8*}*
  %loader.1784 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1778, i32 0, i32 0
  %down.elim.cls.1508 = load i8*, i8** %loader.1784
  %loader.1783 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1778, i32 0, i32 1
  %down.elim.env.1509 = load i8*, i8** %loader.1783
  %fun.1779 = bitcast i8* %down.elim.cls.1508 to i8*
  %arg.1780 = bitcast i8* %arg.1506 to i8*
  %arg.1781 = bitcast i8* %down.elim.env.1509 to i8*
  %cast.1782 = bitcast i8* %fun.1779 to i8* (i8*, i8*)*
  %tmp.1846 = tail call i8* %cast.1782(i8* %arg.1780, i8* %arg.1781)
  ret i8* %tmp.1846
}
define i8* @lam.1514(i8* %arg2.1512, i8* %env.1513) {
  %base.1766 = bitcast i8* %env.1513 to i8*
  %castedBase.1767 = bitcast i8* %base.1766 to {i8*}*
  %loader.1773 = getelementptr {i8*}, {i8*}* %castedBase.1767, i32 0, i32 0
  %arg1.1511 = load i8*, i8** %loader.1773
  %arg.1768 = bitcast i8* %arg1.1511 to i8*
  %arg.1769 = bitcast i8* %arg2.1512 to i8*
  %cast.1770 = ptrtoint i8* %arg.1768 to i32
  %cast.1771 = ptrtoint i8* %arg.1769 to i32
  %result.1772 = mul i32 %cast.1770, %cast.1771
  %result.1847 = inttoptr i32 %result.1772 to i8*
  ret i8* %result.1847
}
define i8* @lam.1516(i8* %arg1.1511, i8* %env.1515) {
  %base.1752 = bitcast i8* %env.1515 to i8*
  %castedBase.1753 = bitcast i8* %base.1752 to {}*
  %cursor.1755 = bitcast i8* (i8*, i8*)* @lam.1514 to i8*
  %cursor.1762 = bitcast i8* %arg1.1511 to i8*
  %sizeptr.1848 = getelementptr i64, i64* null, i32 1
  %size.1849 = ptrtoint i64* %sizeptr.1848 to i64
  %cursor.1756 = call i8* @malloc(i64 %size.1849)
  %cast.1763 = bitcast i8* %cursor.1756 to {i8*}*
  %loader.1764 = getelementptr {i8*}, {i8*}* %cast.1763, i32 0, i32 0
  store i8* %cursor.1762, i8** %loader.1764
  %sizeptr.1850 = getelementptr i64, i64* null, i32 2
  %size.1851 = ptrtoint i64* %sizeptr.1850 to i64
  %ans.1754 = call i8* @malloc(i64 %size.1851)
  %cast.1757 = bitcast i8* %ans.1754 to {i8*, i8*}*
  %loader.1760 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1757, i32 0, i32 0
  store i8* %cursor.1755, i8** %loader.1760
  %loader.1758 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1757, i32 0, i32 1
  store i8* %cursor.1756, i8** %loader.1758
  ret i8* %ans.1754
}
define i8* @lam.1524(i8* %arg2.1522, i8* %env.1523) {
  %base.1744 = bitcast i8* %env.1523 to i8*
  %castedBase.1745 = bitcast i8* %base.1744 to {i8*}*
  %loader.1751 = getelementptr {i8*}, {i8*}* %castedBase.1745, i32 0, i32 0
  %arg1.1521 = load i8*, i8** %loader.1751
  %arg.1746 = bitcast i8* %arg1.1521 to i8*
  %arg.1747 = bitcast i8* %arg2.1522 to i8*
  %cast.1748 = ptrtoint i8* %arg.1746 to i32
  %cast.1749 = ptrtoint i8* %arg.1747 to i32
  %result.1750 = sub i32 %cast.1748, %cast.1749
  %result.1852 = inttoptr i32 %result.1750 to i8*
  ret i8* %result.1852
}
define i8* @lam.1526(i8* %arg1.1521, i8* %env.1525) {
  %base.1730 = bitcast i8* %env.1525 to i8*
  %castedBase.1731 = bitcast i8* %base.1730 to {}*
  %cursor.1733 = bitcast i8* (i8*, i8*)* @lam.1524 to i8*
  %cursor.1740 = bitcast i8* %arg1.1521 to i8*
  %sizeptr.1853 = getelementptr i64, i64* null, i32 1
  %size.1854 = ptrtoint i64* %sizeptr.1853 to i64
  %cursor.1734 = call i8* @malloc(i64 %size.1854)
  %cast.1741 = bitcast i8* %cursor.1734 to {i8*}*
  %loader.1742 = getelementptr {i8*}, {i8*}* %cast.1741, i32 0, i32 0
  store i8* %cursor.1740, i8** %loader.1742
  %sizeptr.1855 = getelementptr i64, i64* null, i32 2
  %size.1856 = ptrtoint i64* %sizeptr.1855 to i64
  %ans.1732 = call i8* @malloc(i64 %size.1856)
  %cast.1735 = bitcast i8* %ans.1732 to {i8*, i8*}*
  %loader.1738 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1735, i32 0, i32 0
  store i8* %cursor.1733, i8** %loader.1738
  %loader.1736 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1735, i32 0, i32 1
  store i8* %cursor.1734, i8** %loader.1736
  ret i8* %ans.1732
}
define i8* @lam.1544(i8* %x.1150, i8* %env.1543) {
  %base.1661 = bitcast i8* %env.1543 to i8*
  %castedBase.1662 = bitcast i8* %base.1661 to {}*
  %ans.1663 = bitcast i8* %x.1150 to i8*
  %tmp.1510 = bitcast i8* %ans.1663 to i8*
  %switch.1728 = bitcast i8* %tmp.1510 to i8*
  %cast.1729 = ptrtoint i8* %switch.1728 to i64
  switch i64 %cast.1729, label %default.1857 [i64 1, label %case.1858]
case.1858:
  %ans.1664 = inttoptr i32 1 to i8*
  ret i8* %ans.1664
default.1857:
  %ans.1665 = inttoptr i32 1 to i8*
  %arg.1531 = bitcast i8* %ans.1665 to i8*
  %ans.1666 = bitcast i8* %x.1150 to i8*
  %arg.1527 = bitcast i8* %ans.1666 to i8*
  %cursor.1668 = bitcast i8* (i8*, i8*)* @lam.1526 to i8*
  %sizeptr.1859 = getelementptr i64, i64* null, i32 0
  %size.1860 = ptrtoint i64* %sizeptr.1859 to i64
  %cursor.1669 = call i8* @malloc(i64 %size.1860)
  %cast.1675 = bitcast i8* %cursor.1669 to {}*
  %sizeptr.1861 = getelementptr i64, i64* null, i32 2
  %size.1862 = ptrtoint i64* %sizeptr.1861 to i64
  %ans.1667 = call i8* @malloc(i64 %size.1862)
  %cast.1670 = bitcast i8* %ans.1667 to {i8*, i8*}*
  %loader.1673 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1670, i32 0, i32 0
  store i8* %cursor.1668, i8** %loader.1673
  %loader.1671 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1670, i32 0, i32 1
  store i8* %cursor.1669, i8** %loader.1671
  %fun.1528 = bitcast i8* %ans.1667 to i8*
  %base.1676 = bitcast i8* %fun.1528 to i8*
  %castedBase.1677 = bitcast i8* %base.1676 to {i8*, i8*}*
  %loader.1683 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1677, i32 0, i32 0
  %down.elim.cls.1529 = load i8*, i8** %loader.1683
  %loader.1682 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1677, i32 0, i32 1
  %down.elim.env.1530 = load i8*, i8** %loader.1682
  %fun.1678 = bitcast i8* %down.elim.cls.1529 to i8*
  %arg.1679 = bitcast i8* %arg.1527 to i8*
  %arg.1680 = bitcast i8* %down.elim.env.1530 to i8*
  %cast.1681 = bitcast i8* %fun.1678 to i8* (i8*, i8*)*
  %fun.1532 = call i8* %cast.1681(i8* %arg.1679, i8* %arg.1680)
  %base.1684 = bitcast i8* %fun.1532 to i8*
  %castedBase.1685 = bitcast i8* %base.1684 to {i8*, i8*}*
  %loader.1691 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1685, i32 0, i32 0
  %down.elim.cls.1533 = load i8*, i8** %loader.1691
  %loader.1690 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1685, i32 0, i32 1
  %down.elim.env.1534 = load i8*, i8** %loader.1690
  %fun.1686 = bitcast i8* %down.elim.cls.1533 to i8*
  %arg.1687 = bitcast i8* %arg.1531 to i8*
  %arg.1688 = bitcast i8* %down.elim.env.1534 to i8*
  %cast.1689 = bitcast i8* %fun.1686 to i8* (i8*, i8*)*
  %arg.1535 = call i8* %cast.1689(i8* %arg.1687, i8* %arg.1688)
  %fun.1692 = bitcast i8* ()* @fact.1149 to i8*
  %cast.1693 = bitcast i8* %fun.1692 to i8* ()*
  %fun.1536 = call i8* %cast.1693()
  %base.1694 = bitcast i8* %fun.1536 to i8*
  %castedBase.1695 = bitcast i8* %base.1694 to {i8*, i8*}*
  %loader.1701 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1695, i32 0, i32 0
  %down.elim.cls.1537 = load i8*, i8** %loader.1701
  %loader.1700 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1695, i32 0, i32 1
  %down.elim.env.1538 = load i8*, i8** %loader.1700
  %fun.1696 = bitcast i8* %down.elim.cls.1537 to i8*
  %arg.1697 = bitcast i8* %arg.1535 to i8*
  %arg.1698 = bitcast i8* %down.elim.env.1538 to i8*
  %cast.1699 = bitcast i8* %fun.1696 to i8* (i8*, i8*)*
  %arg.1539 = call i8* %cast.1699(i8* %arg.1697, i8* %arg.1698)
  %ans.1702 = bitcast i8* %x.1150 to i8*
  %arg.1517 = bitcast i8* %ans.1702 to i8*
  %cursor.1704 = bitcast i8* (i8*, i8*)* @lam.1516 to i8*
  %sizeptr.1863 = getelementptr i64, i64* null, i32 0
  %size.1864 = ptrtoint i64* %sizeptr.1863 to i64
  %cursor.1705 = call i8* @malloc(i64 %size.1864)
  %cast.1711 = bitcast i8* %cursor.1705 to {}*
  %sizeptr.1865 = getelementptr i64, i64* null, i32 2
  %size.1866 = ptrtoint i64* %sizeptr.1865 to i64
  %ans.1703 = call i8* @malloc(i64 %size.1866)
  %cast.1706 = bitcast i8* %ans.1703 to {i8*, i8*}*
  %loader.1709 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1706, i32 0, i32 0
  store i8* %cursor.1704, i8** %loader.1709
  %loader.1707 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1706, i32 0, i32 1
  store i8* %cursor.1705, i8** %loader.1707
  %fun.1518 = bitcast i8* %ans.1703 to i8*
  %base.1712 = bitcast i8* %fun.1518 to i8*
  %castedBase.1713 = bitcast i8* %base.1712 to {i8*, i8*}*
  %loader.1719 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1713, i32 0, i32 0
  %down.elim.cls.1519 = load i8*, i8** %loader.1719
  %loader.1718 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1713, i32 0, i32 1
  %down.elim.env.1520 = load i8*, i8** %loader.1718
  %fun.1714 = bitcast i8* %down.elim.cls.1519 to i8*
  %arg.1715 = bitcast i8* %arg.1517 to i8*
  %arg.1716 = bitcast i8* %down.elim.env.1520 to i8*
  %cast.1717 = bitcast i8* %fun.1714 to i8* (i8*, i8*)*
  %fun.1540 = call i8* %cast.1717(i8* %arg.1715, i8* %arg.1716)
  %base.1720 = bitcast i8* %fun.1540 to i8*
  %castedBase.1721 = bitcast i8* %base.1720 to {i8*, i8*}*
  %loader.1727 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1721, i32 0, i32 0
  %down.elim.cls.1541 = load i8*, i8** %loader.1727
  %loader.1726 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1721, i32 0, i32 1
  %down.elim.env.1542 = load i8*, i8** %loader.1726
  %fun.1722 = bitcast i8* %down.elim.cls.1541 to i8*
  %arg.1723 = bitcast i8* %arg.1539 to i8*
  %arg.1724 = bitcast i8* %down.elim.env.1542 to i8*
  %cast.1725 = bitcast i8* %fun.1722 to i8* (i8*, i8*)*
  %tmp.1867 = tail call i8* %cast.1725(i8* %arg.1723, i8* %arg.1724)
  ret i8* %tmp.1867
}
define i8* @fact.1149() {
  %cursor.1653 = bitcast i8* (i8*, i8*)* @lam.1544 to i8*
  %sizeptr.1868 = getelementptr i64, i64* null, i32 0
  %size.1869 = ptrtoint i64* %sizeptr.1868 to i64
  %cursor.1654 = call i8* @malloc(i64 %size.1869)
  %cast.1660 = bitcast i8* %cursor.1654 to {}*
  %sizeptr.1870 = getelementptr i64, i64* null, i32 2
  %size.1871 = ptrtoint i64* %sizeptr.1870 to i64
  %ans.1652 = call i8* @malloc(i64 %size.1871)
  %cast.1655 = bitcast i8* %ans.1652 to {i8*, i8*}*
  %loader.1658 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1655, i32 0, i32 0
  store i8* %cursor.1653, i8** %loader.1658
  %loader.1656 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1655, i32 0, i32 1
  store i8* %cursor.1654, i8** %loader.1656
  ret i8* %ans.1652
}
define i8* @lam.1547(i8* %arg.1545, i8* %env.1546) {
  %base.1648 = bitcast i8* %env.1546 to i8*
  %castedBase.1649 = bitcast i8* %base.1648 to {}*
  %arg.1650 = bitcast i8* %arg.1545 to i8*
  %cast.1651 = ptrtoint i8* %arg.1650 to i32
  %fmt.1873 = getelementptr [3 x i8], [3 x i8]* @fmt.i32, i32 0, i32 0
  %tmp.1874 = call i32 (i8*, ...) @printf(i8* %fmt.1873, i32 %cast.1651)
  %result.1872 = inttoptr i32 %tmp.1874 to i8*
  ret i8* %result.1872
}
define i8* @lam.1557(i8* %fact.1151, i8* %env.1556) {
  %base.1619 = bitcast i8* %env.1556 to i8*
  %castedBase.1620 = bitcast i8* %base.1619 to {}*
  %ans.1621 = inttoptr i32 10 to i8*
  %arg.1548 = bitcast i8* %ans.1621 to i8*
  %ans.1622 = bitcast i8* %fact.1151 to i8*
  %fun.1549 = bitcast i8* %ans.1622 to i8*
  %base.1623 = bitcast i8* %fun.1549 to i8*
  %castedBase.1624 = bitcast i8* %base.1623 to {i8*, i8*}*
  %loader.1630 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1624, i32 0, i32 0
  %down.elim.cls.1550 = load i8*, i8** %loader.1630
  %loader.1629 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1624, i32 0, i32 1
  %down.elim.env.1551 = load i8*, i8** %loader.1629
  %fun.1625 = bitcast i8* %down.elim.cls.1550 to i8*
  %arg.1626 = bitcast i8* %arg.1548 to i8*
  %arg.1627 = bitcast i8* %down.elim.env.1551 to i8*
  %cast.1628 = bitcast i8* %fun.1625 to i8* (i8*, i8*)*
  %arg.1552 = call i8* %cast.1628(i8* %arg.1626, i8* %arg.1627)
  %cursor.1632 = bitcast i8* (i8*, i8*)* @lam.1547 to i8*
  %sizeptr.1875 = getelementptr i64, i64* null, i32 0
  %size.1876 = ptrtoint i64* %sizeptr.1875 to i64
  %cursor.1633 = call i8* @malloc(i64 %size.1876)
  %cast.1639 = bitcast i8* %cursor.1633 to {}*
  %sizeptr.1877 = getelementptr i64, i64* null, i32 2
  %size.1878 = ptrtoint i64* %sizeptr.1877 to i64
  %ans.1631 = call i8* @malloc(i64 %size.1878)
  %cast.1634 = bitcast i8* %ans.1631 to {i8*, i8*}*
  %loader.1637 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1634, i32 0, i32 0
  store i8* %cursor.1632, i8** %loader.1637
  %loader.1635 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1634, i32 0, i32 1
  store i8* %cursor.1633, i8** %loader.1635
  %fun.1553 = bitcast i8* %ans.1631 to i8*
  %base.1640 = bitcast i8* %fun.1553 to i8*
  %castedBase.1641 = bitcast i8* %base.1640 to {i8*, i8*}*
  %loader.1647 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1641, i32 0, i32 0
  %down.elim.cls.1554 = load i8*, i8** %loader.1647
  %loader.1646 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1641, i32 0, i32 1
  %down.elim.env.1555 = load i8*, i8** %loader.1646
  %fun.1642 = bitcast i8* %down.elim.cls.1554 to i8*
  %arg.1643 = bitcast i8* %arg.1552 to i8*
  %arg.1644 = bitcast i8* %down.elim.env.1555 to i8*
  %cast.1645 = bitcast i8* %fun.1642 to i8* (i8*, i8*)*
  %tmp.1879 = tail call i8* %cast.1645(i8* %arg.1643, i8* %arg.1644)
  ret i8* %tmp.1879
}
define i8* @lam.1563(i8* %io.1137, i8* %env.1562) {
  %base.1598 = bitcast i8* %env.1562 to i8*
  %castedBase.1599 = bitcast i8* %base.1598 to {}*
  %fun.1600 = bitcast i8* ()* @fact.1149 to i8*
  %cast.1601 = bitcast i8* %fun.1600 to i8* ()*
  %arg.1558 = call i8* %cast.1601()
  %cursor.1603 = bitcast i8* (i8*, i8*)* @lam.1557 to i8*
  %sizeptr.1880 = getelementptr i64, i64* null, i32 0
  %size.1881 = ptrtoint i64* %sizeptr.1880 to i64
  %cursor.1604 = call i8* @malloc(i64 %size.1881)
  %cast.1610 = bitcast i8* %cursor.1604 to {}*
  %sizeptr.1882 = getelementptr i64, i64* null, i32 2
  %size.1883 = ptrtoint i64* %sizeptr.1882 to i64
  %ans.1602 = call i8* @malloc(i64 %size.1883)
  %cast.1605 = bitcast i8* %ans.1602 to {i8*, i8*}*
  %loader.1608 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1605, i32 0, i32 0
  store i8* %cursor.1603, i8** %loader.1608
  %loader.1606 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1605, i32 0, i32 1
  store i8* %cursor.1604, i8** %loader.1606
  %fun.1559 = bitcast i8* %ans.1602 to i8*
  %base.1611 = bitcast i8* %fun.1559 to i8*
  %castedBase.1612 = bitcast i8* %base.1611 to {i8*, i8*}*
  %loader.1618 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1612, i32 0, i32 0
  %down.elim.cls.1560 = load i8*, i8** %loader.1618
  %loader.1617 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1612, i32 0, i32 1
  %down.elim.env.1561 = load i8*, i8** %loader.1617
  %fun.1613 = bitcast i8* %down.elim.cls.1560 to i8*
  %arg.1614 = bitcast i8* %arg.1558 to i8*
  %arg.1615 = bitcast i8* %down.elim.env.1561 to i8*
  %cast.1616 = bitcast i8* %fun.1613 to i8* (i8*, i8*)*
  %tmp.1884 = tail call i8* %cast.1616(i8* %arg.1614, i8* %arg.1615)
  ret i8* %tmp.1884
}
define i8* @lam.1570(i8* %state.1116, i8* %env.1569) {
  %base.1575 = bitcast i8* %env.1569 to i8*
  %castedBase.1576 = bitcast i8* %base.1575 to {}*
  %ans.1577 = bitcast i8* %state.1116 to i8*
  %arg.1564 = bitcast i8* %ans.1577 to i8*
  %fun.1578 = bitcast i8* (i8*)* @io.1136 to i8*
  %arg.1579 = bitcast i8* %arg.1564 to i8*
  %cast.1580 = bitcast i8* %fun.1578 to i8* (i8*)*
  %arg.1565 = call i8* %cast.1580(i8* %arg.1579)
  %cursor.1582 = bitcast i8* (i8*, i8*)* @lam.1563 to i8*
  %sizeptr.1885 = getelementptr i64, i64* null, i32 0
  %size.1886 = ptrtoint i64* %sizeptr.1885 to i64
  %cursor.1583 = call i8* @malloc(i64 %size.1886)
  %cast.1589 = bitcast i8* %cursor.1583 to {}*
  %sizeptr.1887 = getelementptr i64, i64* null, i32 2
  %size.1888 = ptrtoint i64* %sizeptr.1887 to i64
  %ans.1581 = call i8* @malloc(i64 %size.1888)
  %cast.1584 = bitcast i8* %ans.1581 to {i8*, i8*}*
  %loader.1587 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1584, i32 0, i32 0
  store i8* %cursor.1582, i8** %loader.1587
  %loader.1585 = getelementptr {i8*, i8*}, {i8*, i8*}* %cast.1584, i32 0, i32 1
  store i8* %cursor.1583, i8** %loader.1585
  %fun.1566 = bitcast i8* %ans.1581 to i8*
  %base.1590 = bitcast i8* %fun.1566 to i8*
  %castedBase.1591 = bitcast i8* %base.1590 to {i8*, i8*}*
  %loader.1597 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1591, i32 0, i32 0
  %down.elim.cls.1567 = load i8*, i8** %loader.1597
  %loader.1596 = getelementptr {i8*, i8*}, {i8*, i8*}* %castedBase.1591, i32 0, i32 1
  %down.elim.env.1568 = load i8*, i8** %loader.1596
  %fun.1592 = bitcast i8* %down.elim.cls.1567 to i8*
  %arg.1593 = bitcast i8* %arg.1565 to i8*
  %arg.1594 = bitcast i8* %down.elim.env.1568 to i8*
  %cast.1595 = bitcast i8* %fun.1592 to i8* (i8*, i8*)*
  %tmp.1889 = tail call i8* %cast.1595(i8* %arg.1593, i8* %arg.1594)
  ret i8* %tmp.1889
}